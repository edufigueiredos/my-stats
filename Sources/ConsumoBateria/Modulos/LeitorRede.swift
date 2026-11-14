import CoreWLAN
import Foundation
import Network
import SystemConfiguration

/// Rede: velocidade da interface primária, total do dia, Wi-Fi (CoreWLAN), latência (TCP), IP, roteador, DNS e,
/// com o painel aberto, quem mais usa a rede (nettop). Sem root; toda falha vira nil.
@MainActor
final class LeitorRede {
    private struct Contadores { var entrada: UInt32; var saida: UInt32; var data: Date }
    private struct Hoje: Codable { var dia: String; var baixado: UInt64; var enviado: UInt64 }

    private let persistir: Bool
    private let store = SCDynamicStoreCreate(nil, "ConsumoBateria" as CFString, nil, nil)
    private var anterior: (interface: String, contadores: Contadores)?
    private var baixandoBps = 0.0, enviandoBps = 0.0
    private var hoje: Hoje
    private var ultimaGravacao = Date.distantPast

    // Latência
    private var resultados: [Double?] = []
    private var ultimoPing = Date.distantPast
    private var pingEmCurso = false
    private var latenciaRoteador: Double?
    private var ultimoPingRoteador = Date.distantPast
    private var pingRoteadorEmCurso = false

    // Processos
    private(set) var processos: [ProcessoUso]?
    private var ultimaMedicaoProcessos = Date.distantPast
    private var medindoProcessos = false
    private var falhasNettop = 0
    private var desistiuNettop = false
    private var anteriorNettop: (bytes: [String: (Double, Double)], data: Date)?

    init(persistir: Bool = true) {
        self.persistir = persistir
        let dia = Self.diaAtual()
        if persistir, let dados = UserDefaults.standard.data(forKey: "redeHoje"),
           let salvo = try? JSONDecoder().decode(Hoje.self, from: dados), salvo.dia == dia {
            hoje = salvo
        } else {
            hoje = Hoje(dia: dia, baixado: 0, enviado: 0)
        }
    }

    // MARK: Leitura

    func ler() -> LeituraRede? {
        let global = valor("State:/Network/Global/IPv4")
        guard let interface = global?["PrimaryInterface"] as? String else {
            anterior = nil; baixandoBps = 0; enviandoBps = 0
            return LeituraRede(conectado: false)
        }
        var r = LeituraRede(conectado: true)
        atualizarVelocidade(interface: interface)
        r.baixandoBps = baixandoBps
        r.enviandoBps = enviandoBps
        r.hojeBaixadoBytes = hoje.baixado
        r.hojeEnviadoBytes = hoje.enviado
        r.ipLocal = Self.enderecoIPv4(interface)
        r.roteador = global?["Router"] as? String
        r.dns = (valor("State:/Network/Global/DNS")?["ServerAddresses"] as? [String]) ?? []
        r.latenciaRoteadorMs = latenciaRoteador

        let wifi = CWWiFiClient.shared().interface()
        if let wifi, wifi.interfaceName == interface {
            r.tipo = "Wi-Fi"
            preencherWiFi(wifi, em: &r)
        } else {
            r.tipo = interface.hasPrefix("en") ? "Ethernet" : "Rede"
        }

        let validos = resultados.compactMap { $0 }
        r.latenciaMs = resultados.last ?? nil // última medição; perda = nil
        if validos.count >= 2 {
            var soma = 0.0
            for i in 1..<validos.count { soma += abs(validos[i] - validos[i - 1]) }
            r.variacaoMs = soma / Double(validos.count - 1)
        }
        if !resultados.isEmpty { r.perdaPercentual = Double(resultados.count - validos.count) / Double(resultados.count) * 100 }
        return r
    }

    private func valor(_ chave: String) -> [String: Any]? {
        guard let store else { return nil }
        return SCDynamicStoreCopyValue(store, chave as CFString) as? [String: Any]
    }

    private func preencherWiFi(_ wifi: CWInterface, em r: inout LeituraRede) {
        r.nomeRede = wifi.ssid() // nil sem permissão de localização: a tela mostra só "Wi-Fi"
        let rssi = wifi.rssiValue()
        if rssi != 0 { r.sinalDbm = rssi }
        let ruido = wifi.noiseMeasurement()
        if ruido != 0 { r.ruidoDbm = ruido }
        let taxa = wifi.transmitRate()
        if taxa > 0 { r.velocidadeLinkMbps = taxa }
        var banda6 = false
        if let canal = wifi.wlanChannel() {
            switch canal.channelBand {
            case .band2GHz: r.banda = "2,4 GHz"
            case .band5GHz: r.banda = "5 GHz"
            case .band6GHz: r.banda = "6 GHz"; banda6 = true
            default: break
            }
            let largura: Int?
            switch canal.channelWidth {
            case .width20MHz: largura = 20
            case .width40MHz: largura = 40
            case .width80MHz: largura = 80
            case .width160MHz: largura = 160
            default: largura = nil
            }
            r.canal = largura.map { "\(canal.channelNumber) · \($0) MHz" } ?? "\(canal.channelNumber)"
        }
        switch wifi.activePHYMode() {
        case .mode11n: r.padraoWiFi = "Wi-Fi 4"
        case .mode11ac: r.padraoWiFi = "Wi-Fi 5"
        case .mode11ax: r.padraoWiFi = banda6 ? "Wi-Fi 6E" : "Wi-Fi 6"
        case .mode11be: r.padraoWiFi = "Wi-Fi 7"
        default: break
        }
    }

    // MARK: Velocidade e total do dia

    private func atualizarVelocidade(interface: String) {
        guard let atual = Self.contadores(interface) else { return }
        if let ant = anterior, ant.interface == interface {
            let dt = atual.data.timeIntervalSince(ant.contadores.data)
            if dt > Self.intervaloMaximo {
                // Tempo desligado/suspenso ou contador que deu voltas: não soma em "hoje".
                baixandoBps = 0; enviandoBps = 0
                anterior = (interface, atual)
            } else if dt > 0.2 {
                // Contadores de 32 bits dão a volta: a subtração com wrap devolve o delta certo.
                let dEntrada = Double(atual.entrada &- ant.contadores.entrada)
                let dSaida = Double(atual.saida &- ant.contadores.saida)
                baixandoBps = dEntrada / dt
                enviandoBps = dSaida / dt
                let dia = Self.diaAtual()
                if dia != hoje.dia { hoje = Hoje(dia: dia, baixado: 0, enviado: 0) }
                hoje.baixado += UInt64(dEntrada)
                hoje.enviado += UInt64(dSaida)
                gravarHoje()
                anterior = (interface, atual)
            }
        } else {
            baixandoBps = 0; enviandoBps = 0
            anterior = (interface, atual)
        }
    }

    /// Acima disso entre duas amostras, o delta de bytes é descartado.
    private static let intervaloMaximo: TimeInterval = 15

    /// Grava o total do dia na hora (ao encerrar o app).
    func gravarAgora() { gravarHoje(forcar: true) }

    private func gravarHoje(forcar: Bool = false) {
        guard persistir, forcar || Date().timeIntervalSince(ultimaGravacao) >= 60 else { return }
        ultimaGravacao = Date()
        if let dados = try? JSONEncoder().encode(hoje) { UserDefaults.standard.set(dados, forKey: "redeHoje") }
    }

    private static func diaAtual() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func contadores(_ interface: String) -> Contadores? {
        var lista: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&lista) == 0, let primeiro = lista else { return nil }
        defer { freeifaddrs(lista) }
        var p: UnsafeMutablePointer<ifaddrs>? = primeiro
        while let atual = p {
            defer { p = atual.pointee.ifa_next }
            guard let end = atual.pointee.ifa_addr, end.pointee.sa_family == UInt8(AF_LINK),
                  String(cString: atual.pointee.ifa_name) == interface,
                  let dados = atual.pointee.ifa_data else { continue }
            let d = dados.assumingMemoryBound(to: if_data.self).pointee
            return Contadores(entrada: d.ifi_ibytes, saida: d.ifi_obytes, data: Date())
        }
        return nil
    }

    private static func enderecoIPv4(_ interface: String) -> String? {
        var lista: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&lista) == 0, let primeiro = lista else { return nil }
        defer { freeifaddrs(lista) }
        var p: UnsafeMutablePointer<ifaddrs>? = primeiro
        while let atual = p {
            defer { p = atual.pointee.ifa_next }
            guard let end = atual.pointee.ifa_addr, end.pointee.sa_family == UInt8(AF_INET),
                  String(cString: atual.pointee.ifa_name) == interface else { continue }
            var nome = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(end, socklen_t(end.pointee.sa_len), &nome, socklen_t(nome.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(decoding: nome.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }
        return nil
    }

    // MARK: Latência

    /// No máximo a cada 5 s (internet) e 30 s (roteador). O resultado entra na próxima `ler()`.
    func pingarSePreciso() {
        guard valor("State:/Network/Global/IPv4")?["PrimaryInterface"] != nil else {
            resultados = []; latenciaRoteador = nil
            return
        }
        let agora = Date()
        if !pingEmCurso, agora.timeIntervalSince(ultimoPing) >= 5 {
            pingEmCurso = true
            ultimoPing = agora
            Task { [weak self] in
                let ms = await MedidorTCP.medir(host: "1.1.1.1", porta: 443, limite: 2)
                self?.registrarPing(ms)
            }
        }
        if !pingRoteadorEmCurso, agora.timeIntervalSince(ultimoPingRoteador) >= 30,
           let roteador = valor("State:/Network/Global/IPv4")?["Router"] as? String {
            pingRoteadorEmCurso = true
            ultimoPingRoteador = agora
            Task { [weak self] in
                let ms = await MedidorTCP.medir(host: roteador, porta: 80, limite: 2)
                self?.latenciaRoteador = ms
                self?.pingRoteadorEmCurso = false
            }
        }
    }

    private func registrarPing(_ ms: Double?) {
        pingEmCurso = false
        resultados.append(ms)
        if resultados.count > 20 { resultados.removeFirst(resultados.count - 20) }
    }

    // MARK: Processos (nettop)

    func medirProcessosSePreciso() {
        guard !desistiuNettop, !medindoProcessos, Date().timeIntervalSince(ultimaMedicaoProcessos) >= 5 else { return }
        medindoProcessos = true
        ultimaMedicaoProcessos = Date()
        Task { [weak self] in
            let saida = await Self.executarNettop()
            self?.receberNettop(saida)
        }
    }

    private func receberNettop(_ saida: String?) {
        medindoProcessos = false
        guard let saida else {
            falhasNettop += 1
            if falhasNettop >= 2 { desistiuNettop = true; processos = nil }
            return
        }
        falhasNettop = 0
        let agora = Date()
        var atual: [String: (Double, Double)] = [:]
        for linha in saida.split(separator: "\n") {
            let campos = linha.split(separator: ",", omittingEmptySubsequences: false)
            guard campos.count >= 3, let entrada = Double(campos[1]), let saidaB = Double(campos[2]) else { continue }
            atual[String(campos[0])] = (entrada, saidaB)
        }
        defer { anteriorNettop = (atual, agora) }
        guard let ant = anteriorNettop, !atual.isEmpty else { return }
        let dt = agora.timeIntervalSince(ant.data)
        guard dt > 0.5 else { return }
        var porNome: [String: (Double, Double)] = [:]
        for (chave, v) in atual {
            guard let antes = ant.bytes[chave] else { continue }
            let d = (max(v.0 - antes.0, 0) / dt, max(v.1 - antes.1, 0) / dt)
            guard d.0 > 0 || d.1 > 0 else { continue }
            var nome = chave
            if let ponto = chave.lastIndex(of: "."), Int(chave[chave.index(after: ponto)...]) != nil { nome = String(chave[..<ponto]) }
            let acumulado = porNome[nome] ?? (0, 0)
            porNome[nome] = (acumulado.0 + d.0, acumulado.1 + d.1)
        }
        let ordenados = porNome.sorted { $0.value.0 + $0.value.1 > $1.value.0 + $1.value.1 }.prefix(3)
        let maior = ordenados.first.map { $0.value.0 + $0.value.1 } ?? 0
        processos = ordenados.map {
            ProcessoUso(id: $0.key, nome: $0.key, valor: $0.value.0, valor2: $0.value.1,
                        fracao: maior > 0 ? ($0.value.0 + $0.value.1) / maior : 0)
        }
    }

    /// Roda o nettop com limite de 3 s; nil se falhar ou estourar o tempo. Não bloqueia threads do pool.
    private nonisolated static func executarNettop() async -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        p.arguments = ["-n", "-P", "-L", "1", "-x", "-J", "bytes_in,bytes_out"] // -n: sem resolver nomes (senão leva 5 s)
        let cano = Pipe()
        p.standardOutput = cano
        p.standardError = FileHandle.nullDevice
        let buffer = BufferSeguro()
        cano.fileHandleForReading.readabilityHandler = { h in buffer.acrescentar(h.availableData) }
        let terminou: Bool = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            let uma = UmaVez(c)
            p.terminationHandler = { _ in uma.concluir(true) }
            do { try p.run() } catch { uma.concluir(false); return }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
                if uma.concluir(false) { p.terminate() }
            }
        }
        cano.fileHandleForReading.readabilityHandler = nil
        guard terminou else { return nil }
        buffer.acrescentar(cano.fileHandleForReading.availableData)
        guard p.terminationStatus == 0 else { return nil }
        let texto = String(decoding: buffer.dados, as: UTF8.self)
        return texto.isEmpty ? nil : texto
    }

    // MARK: IP público

    /// Só quando o usuário clica em "Mostrar".
    static func buscarIPPublico() async -> String? {
        guard let url = URL(string: "https://api.ipify.org") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        guard let (dados, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let t = String(decoding: dados, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t.count > 45 ? nil : t
    }
}

/// Retoma a continuação uma só vez; `concluir` devolve se foi a primeira chamada.
private final class UmaVez: @unchecked Sendable {
    private let trava = NSLock()
    private var feito = false
    private let continuacao: CheckedContinuation<Bool, Never>
    init(_ c: CheckedContinuation<Bool, Never>) { continuacao = c }
    @discardableResult
    func concluir(_ v: Bool) -> Bool {
        trava.lock(); let primeira = !feito; feito = true; trava.unlock()
        if primeira { continuacao.resume(returning: v) }
        return primeira
    }
}

private final class BufferSeguro: @unchecked Sendable {
    private let trava = NSLock()
    private var _dados = Data()
    func acrescentar(_ d: Data) { trava.lock(); _dados.append(d); trava.unlock() }
    var dados: Data { trava.lock(); defer { trava.unlock() }; return _dados }
}

/// Mede o tempo até a conexão TCP ficar pronta. Conexão recusada (RST) também conta como tempo; estourar o limite é perda.
private enum MedidorTCP {
    private final class Uma: @unchecked Sendable {
        private let trava = NSLock()
        private var feito = false
        private let continuacao: CheckedContinuation<Double?, Never>
        init(_ c: CheckedContinuation<Double?, Never>) { continuacao = c }
        func concluir(_ v: Double?) {
            trava.lock(); let primeira = !feito; feito = true; trava.unlock()
            if primeira { continuacao.resume(returning: v) }
        }
    }

    static func medir(host: String, porta: UInt16, limite: TimeInterval) async -> Double? {
        guard let p = NWEndpoint.Port(rawValue: porta) else { return nil }
        return await withCheckedContinuation { (c: CheckedContinuation<Double?, Never>) in
            let uma = Uma(c)
            let conexao = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
            let fila = DispatchQueue(label: "consumobateria.ping")
            let inicio = DispatchTime.now()
            let decorrido: @Sendable () -> Double = { Double(DispatchTime.now().uptimeNanoseconds - inicio.uptimeNanoseconds) / 1e6 }
            conexao.stateUpdateHandler = { estado in
                switch estado {
                case .ready:
                    uma.concluir(decorrido()); conexao.cancel()
                case .failed(let erro), .waiting(let erro):
                    if case .posix(let codigo) = erro, codigo == .ECONNREFUSED { uma.concluir(decorrido()) } else if case .failed = estado { uma.concluir(nil) }
                    if case .failed = estado { conexao.cancel() }
                    if case .posix(let codigo) = erro, codigo == .ECONNREFUSED { conexao.cancel() }
                default: break
                }
            }
            fila.asyncAfter(deadline: .now() + limite) { uma.concluir(nil); conexao.cancel() }
            conexao.start(queue: fila)
        }
    }
}
