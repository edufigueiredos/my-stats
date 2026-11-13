import Foundation

// MARK: - Tipos públicos

/// Períodos da janela Mais informações.
enum Periodo: String, CaseIterable, Sendable, Identifiable {
    case hoje, seteDias, trintaDias

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .hoje: return "Hoje"
        case .seteDias: return "7 dias"
        case .trintaDias: return "30 dias"
        }
    }

    var dias: Int {
        switch self {
        case .hoje: return 1
        case .seteDias: return 7
        case .trintaDias: return 30
        }
    }

    /// Do início do primeiro dia do período até `ate`.
    func intervalo(ate: Date) -> DateInterval {
        let cal = Calendar.current
        let hoje = cal.startOfDay(for: ate)
        let inicio = cal.date(byAdding: .day, value: -(dias - 1), to: hoje) ?? hoje
        return DateInterval(start: inicio, end: max(ate, inicio))
    }
}

enum TipoTrecho: String, Sendable {
    case naBateria, carregando, naTomadaParado

    var titulo: String {
        switch self {
        case .naBateria: return "Na bateria"
        case .carregando: return "Carregando"
        case .naTomadaParado: return "Na tomada"
        }
    }
}

/// Um trecho contínuo do histórico no mesmo estado.
struct Trecho: Identifiable, Sendable, Equatable {
    var id: Date { inicio }
    var tipo: TipoTrecho
    var inicio: Date
    var fim: Date
    var percentualInicio: Double
    var percentualFim: Double
    /// %/h médio, com sinal.
    var ritmoMedio: Double
    /// Potência média, em módulo.
    var wattsMedio: Double
}

/// Os 4 números do topo da janela (rótulos de Detalhes.dc.html).
struct ResumoPeriodo: Sendable, Equatable {
    /// "Média na bateria": %/h (negativo) e W em média (módulo).
    var ritmoMedioBateria: Double?
    var wattsMedioBateria: Double?
    /// "Pior hora": o ritmo mais negativo numa hora cheia e o início dela.
    var piorHoraRitmo: Double?
    var piorHoraInicio: Date?
    /// "Tempo na bateria" e "desde" (primeiro minuto na bateria do período).
    var tempoNaBateria: TimeInterval
    var desde: Date?
    /// "Carregou": quantas vezes, quanto subiu (soma de pontos percentuais) e por quantos minutos.
    var cargas: Int
    var ganhoCarga: Double
    var minutosCarregando: Double
    /// Energia tirada da bateria no período, em Wh.
    var energiaUsadaWh: Double

    static let vazio = ResumoPeriodo(
        ritmoMedioBateria: nil, wattsMedioBateria: nil, piorHoraRitmo: nil, piorHoraInicio: nil,
        tempoNaBateria: 0, desde: nil, cargas: 0, ganhoCarga: 0, minutosCarregando: 0, energiaUsadaWh: 0)
}

struct GastoApp: Identifiable, Sendable, Equatable {
    var id: String { nome }
    var nome: String
    var wh: Double
}

// MARK: - Histórico

/// Histórico de até 90 dias, 1 ponto por minuto, um arquivo binário comprimido por dia.
@MainActor
final class Historico {
    private struct Dia {
        var inicio: Date
        var pontos: [PontoMinuto] = []
        var apps: [String: Double] = [:]
        var alterado = false
    }

    private struct Acumulado {
        var minuto: Date
        var somaRitmo = 0.0
        var somaWatts = 0.0
        var n = 0
        var percentual = 0.0
        var naTomada = false
        var carregando = false

        var ponto: PontoMinuto {
            PontoMinuto(data: minuto, percentual: percentual, ritmo: n > 0 ? somaRitmo / Double(n) : 0,
                        watts: n > 0 ? somaWatts / Double(n) : 0, naTomada: naTomada, carregando: carregando)
        }
    }

    /// Quantos dias ficam guardados; ao mudar, apaga o que passou do corte.
    var diasGuardados: Int {
        didSet {
            diasGuardados = min(max(diasGuardados, 1), 365)
            if diasGuardados != oldValue { podar() }
        }
    }

    private let pasta: URL?
    private let emMemoria: Bool
    private var cache: [Date: Dia] = [:]
    private var acumulado: Acumulado?
    private var minutosDesdeSalvar = 0
    private var diaDaPoda: Date
    private let cal = Calendar.current
    private static let maxDiasEmCache = 8

    init(pasta: URL? = nil, dias: Int = 90, emMemoria: Bool = false) {
        self.emMemoria = emMemoria
        self.diasGuardados = min(max(dias, 1), 365)
        self.diaDaPoda = Calendar.current.startOfDay(for: Date())
        if emMemoria {
            self.pasta = nil
        } else {
            let padrao = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ConsumoBateria", isDirectory: true)
                .appendingPathComponent("historico", isDirectory: true)
            self.pasta = pasta ?? padrao
            try? FileManager.default.createDirectory(at: self.pasta!, withIntermediateDirectories: true)
        }
        podar()
    }

    // MARK: Gravação

    /// Recebe leituras (~a cada 5 s) e consolida 1 ponto por minuto.
    func registrar(_ p: PontoMinuto) {
        let minuto = Date(timeIntervalSinceReferenceDate: (p.data.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
        if let a = acumulado, a.minuto != minuto {
            fechar(a)
            acumulado = nil
        }
        var a = acumulado ?? Acumulado(minuto: minuto)
        a.somaRitmo += p.ritmo
        a.somaWatts += p.watts
        a.n += 1
        a.percentual = p.percentual
        a.naTomada = p.naTomada
        a.carregando = p.carregando
        acumulado = a
    }

    /// Acumula Wh por app no dia de hoje (watts x segundos / 3600).
    func registrarApps(_ apps: [ConsumoApp], segundos: TimeInterval) {
        guard !apps.isEmpty, segundos > 0 else { return }
        let inicio = cal.startOfDay(for: Date())
        var dia = dia(inicio, criar: true) ?? Dia(inicio: inicio)
        for app in apps where app.watts > 0 {
            dia.apps[app.nome, default: 0] += app.watts * segundos / 3600
        }
        dia.alterado = true
        cache[inicio] = dia
    }

    private func fechar(_ a: Acumulado) {
        adicionar(a.ponto)
        minutosDesdeSalvar += 1
        if minutosDesdeSalvar >= 10 { salvar() }
        let hoje = cal.startOfDay(for: a.minuto)
        if hoje != diaDaPoda {
            diaDaPoda = hoje
            podar()
        }
    }

    private func adicionar(_ ponto: PontoMinuto) {
        let inicio = cal.startOfDay(for: ponto.data)
        var dia = dia(inicio, criar: true) ?? Dia(inicio: inicio)
        if let ultimo = dia.pontos.last, ultimo.data >= ponto.data {
            dia.pontos.removeAll { $0.data == ponto.data }
            dia.pontos.append(ponto)
            dia.pontos.sort { $0.data < $1.data }
        } else {
            dia.pontos.append(ponto)
        }
        dia.alterado = true
        cache[inicio] = dia
        enxugarCache()
    }

    /// Grava os dias alterados (inclui o minuto em andamento).
    func salvar() {
        minutosDesdeSalvar = 0
        guard !emMemoria, let pasta else { return }
        if let a = acumulado, a.n > 0 { adicionar(a.ponto) }
        try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        for (chave, dia) in cache where dia.alterado {
            do {
                try Self.codificar(dia).write(to: arquivo(chave), options: .atomic)
                cache[chave]?.alterado = false
            } catch {
                NSLog("ConsumoBateria: não gravou o histórico de \(chave): \(error)")
            }
        }
        enxugarCache()
    }

    // MARK: Leitura

    func pontos(de: Date, ate: Date) -> [PontoMinuto] {
        guard de <= ate else { return [] }
        var saida: [PontoMinuto] = []
        var inicio = cal.startOfDay(for: de)
        while inicio <= ate {
            if let dia = dia(inicio, criar: false) {
                saida += dia.pontos.filter { $0.data >= de && $0.data <= ate }
            }
            guard let proximo = cal.date(byAdding: .day, value: 1, to: inicio) else { break }
            inicio = proximo
        }
        if let a = acumulado, a.n > 0, a.minuto >= de, a.minuto <= ate,
           saida.last.map({ $0.data < a.minuto }) ?? true {
            saida.append(a.ponto)
        }
        enxugarCache()
        return saida
    }

    func resumo(_ p: Periodo, agora: Date = .now) -> ResumoPeriodo {
        let iv = p.intervalo(ate: agora)
        return resumo(pontos: pontos(de: iv.start, ate: iv.end))
    }

    /// Resumo a partir de pontos já lidos (evita reler o disco).
    func resumo(pontos: [PontoMinuto]) -> ResumoPeriodo {
        let bateria = pontos.filter { !$0.naTomada }
        var r = ResumoPeriodo.vazio
        if !bateria.isEmpty {
            let n = Double(bateria.count)
            r.ritmoMedioBateria = bateria.reduce(0) { $0 + $1.ritmo } / n
            r.wattsMedioBateria = bateria.reduce(0) { $0 + abs($1.watts) } / n
            r.tempoNaBateria = n * 60
            r.desde = bateria.first?.data
            r.energiaUsadaWh = bateria.reduce(0) { $0 + abs($1.watts) } / 60
            // Pior hora: a hora cheia com o ritmo médio mais negativo (mínimo de 20 minutos na bateria).
            var horas: [Date: (soma: Double, n: Int)] = [:]
            for b in bateria {
                let h = cal.dateInterval(of: .hour, for: b.data)?.start ?? b.data
                let atual = horas[h] ?? (0, 0)
                horas[h] = (atual.soma + b.ritmo, atual.n + 1)
            }
            let pior = horas.filter { $0.value.n >= 20 }
                .map { ($0.key, $0.value.soma / Double($0.value.n)) }
                .min { $0.1 < $1.1 }
            r.piorHoraInicio = pior?.0
            r.piorHoraRitmo = pior?.1
        }
        let cargas = Self.montarTrechos(pontos).filter { $0.tipo == .carregando }
        r.cargas = cargas.count
        r.ganhoCarga = cargas.reduce(0) { $0 + max(0, $1.percentualFim - $1.percentualInicio) }
        r.minutosCarregando = cargas.reduce(0) { $0 + $1.fim.timeIntervalSince($1.inicio) / 60 }
        return r
    }

    /// Trechos do período, do mais recente para o mais antigo.
    func trechos(_ p: Periodo, agora: Date = .now) -> [Trecho] {
        let iv = p.intervalo(ate: agora)
        return trechos(pontos: pontos(de: iv.start, ate: iv.end))
    }

    /// Trechos a partir de pontos já lidos, do mais recente para o mais antigo.
    func trechos(pontos: [PontoMinuto]) -> [Trecho] {
        Self.montarTrechos(pontos).reversed()
    }

    /// Os 5 que mais gastaram, mais "Outros" se houver mais; em Wh.
    func quemMaisGastou(_ p: Periodo) -> [GastoApp] {
        let iv = p.intervalo(ate: .now)
        var total: [String: Double] = [:]
        var inicio = cal.startOfDay(for: iv.start)
        while inicio <= iv.end {
            if let dia = dia(inicio, criar: false) {
                for (nome, wh) in dia.apps { total[nome, default: 0] += wh }
            }
            guard let proximo = cal.date(byAdding: .day, value: 1, to: inicio) else { break }
            inicio = proximo
        }
        enxugarCache()
        let outros = total["Outros"] ?? 0
        let ordenado = total.filter { $0.key != "Outros" }.sorted { $0.value > $1.value }
        let limite = outros > 0 ? 5 : 6
        let cabeca = ordenado.count > limite ? Array(ordenado.prefix(limite - (outros > 0 ? 0 : 1))) : ordenado
        let resto = ordenado.dropFirst(cabeca.count).reduce(outros) { $0 + $1.value }
        var saida = cabeca.map { GastoApp(nome: $0.key, wh: $0.value) }
        if resto > 0 { saida.append(GastoApp(nome: "Outros", wh: resto)) }
        return saida
    }

    func csv(_ p: Periodo) -> String {
        let iv = p.intervalo(ate: .now)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
        func n(_ v: Double) -> String { String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",") }
        var linhas = ["data;percentual;ritmo_%h;watts;na_tomada;carregando"]
        for p in pontos(de: iv.start, ate: iv.end) {
            linhas.append("\(f.string(from: p.data));\(n(p.percentual));\(n(p.ritmo));\(n(p.watts));\(p.naTomada ? 1 : 0);\(p.carregando ? 1 : 0)")
        }
        return linhas.joined(separator: "\n") + "\n"
    }

    // MARK: Trechos

    private struct Bloco {
        var tipo: TipoTrecho
        var pontos: [PontoMinuto]
    }

    nonisolated private static func tipo(_ p: PontoMinuto) -> TipoTrecho {
        p.carregando ? .carregando : (p.naTomada ? .naTomadaParado : .naBateria)
    }

    /// Do mais antigo para o mais novo. Corta quando o estado muda ou há lacuna de mais de 10 min;
    /// blocos com menos de 2 pontos entram no vizinho.
    nonisolated private static func montarTrechos(_ pontos: [PontoMinuto]) -> [Trecho] {
        var blocos: [Bloco] = []
        var anterior: PontoMinuto?
        for p in pontos {
            let t = tipo(p)
            let lacuna = anterior.map { p.data.timeIntervalSince($0.data) > 10 * 60 } ?? false
            if let ultimo = blocos.last, ultimo.tipo == t, !lacuna {
                blocos[blocos.count - 1].pontos.append(p)
            } else {
                blocos.append(Bloco(tipo: t, pontos: [p]))
            }
            anterior = p
        }
        // Absorve os blocos curtos pelo vizinho anterior (ou pelo seguinte, se for o primeiro).
        var i = 0
        while i < blocos.count, blocos.count > 1 {
            if blocos[i].pontos.count < 2 {
                let curto = blocos.remove(at: i)
                if i > 0 {
                    blocos[i - 1].pontos += curto.pontos
                } else {
                    blocos[0].pontos = curto.pontos + blocos[0].pontos
                }
                // Une vizinhos que ficaram do mesmo tipo.
                var j = max(i - 1, 0)
                while j + 1 < blocos.count {
                    if blocos[j].tipo == blocos[j + 1].tipo {
                        blocos[j].pontos += blocos[j + 1].pontos
                        blocos.remove(at: j + 1)
                    } else { j += 1 }
                }
                i = 0
            } else {
                i += 1
            }
        }
        return blocos.compactMap { b in
            guard let primeiro = b.pontos.first, let ultimo = b.pontos.last else { return nil }
            let n = Double(b.pontos.count)
            return Trecho(
                tipo: b.tipo, inicio: primeiro.data, fim: ultimo.data,
                percentualInicio: primeiro.percentual, percentualFim: ultimo.percentual,
                ritmoMedio: b.pontos.reduce(0) { $0 + $1.ritmo } / n,
                wattsMedio: b.pontos.reduce(0) { $0 + abs($1.watts) } / n)
        }
    }

    // MARK: Disco e cache

    private func chave(_ inicio: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: inicio)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func arquivo(_ inicio: Date) -> URL {
        pasta!.appendingPathComponent(chave(inicio) + ".bin")
    }

    private func arquivo(_ chave: String) -> URL { pasta!.appendingPathComponent(chave + ".bin") }

    private func dia(_ inicio: Date, criar: Bool) -> Dia? {
        if let d = cache[inicio] { return d }
        if let pasta, !emMemoria,
           let dados = try? Data(contentsOf: pasta.appendingPathComponent(chave(inicio) + ".bin")),
           let d = Self.decodificar(dados, inicio: inicio) {
            cache[inicio] = d
            return d
        }
        return criar ? Dia(inicio: inicio) : nil
    }

    private func enxugarCache() {
        guard cache.count > Self.maxDiasEmCache else { return }
        let limpos = cache.filter { !$0.value.alterado }.keys.sorted()
        var sobra = cache.count - Self.maxDiasEmCache
        for k in limpos where sobra > 0 {
            if emMemoria { break }   // em memória o cache é o único armazenamento
            cache[k] = nil
            sobra -= 1
        }
    }

    /// Apaga arquivos e dias mais velhos que `diasGuardados`.
    private func podar() {
        let hoje = cal.startOfDay(for: Date())
        guard let corte = cal.date(byAdding: .day, value: -(diasGuardados - 1), to: hoje) else { return }
        for k in cache.keys where k < corte { cache[k] = nil }
        guard !emMemoria, let pasta,
              let nomes = try? FileManager.default.contentsOfDirectory(atPath: pasta.path) else { return }
        for nome in nomes where nome.hasSuffix(".bin") {
            let partes = nome.dropLast(4).split(separator: "-").compactMap { Int($0) }
            guard partes.count == 3,
                  let data = cal.date(from: DateComponents(year: partes[0], month: partes[1], day: partes[2])) else { continue }
            if data < corte { try? FileManager.default.removeItem(at: arquivo(String(nome.dropLast(4)))) }
        }
    }

    // MARK: Formato binário

    // v1: [versão u8][n u16] n x [minuto u16, pct x10 u16, ritmo x10 i16, watts x10 i16, flags u8]
    //     [nApps u16] nApps x [len u8, nome utf8, wh f32]; tudo em little-endian, comprimido com lzfse.
    nonisolated private static func codificar(_ dia: Dia) throws -> Data {
        var b: [UInt8] = [1]
        func u16(_ v: UInt16) { b.append(UInt8(v & 0xFF)); b.append(UInt8(v >> 8)) }
        func limitar(_ v: Double) -> Int16 { Int16(max(-32000, min(32000, (v * 10).rounded()))) }
        let pontos = dia.pontos.prefix(3000)
        u16(UInt16(pontos.count))
        for p in pontos {
            let minuto = Int(p.data.timeIntervalSince(dia.inicio) / 60)
            u16(UInt16(max(0, min(minuto, 65535))))
            u16(UInt16(max(0, min(p.percentual * 10, 1000)).rounded()))
            u16(UInt16(bitPattern: limitar(p.ritmo)))
            u16(UInt16(bitPattern: limitar(p.watts)))
            b.append((p.naTomada ? 1 : 0) | (p.carregando ? 2 : 0))
        }
        let apps = dia.apps.sorted { $0.value > $1.value }.prefix(60)
        u16(UInt16(apps.count))
        for (nome, wh) in apps {
            let bytes = Array(nome.utf8.prefix(255))
            b.append(UInt8(bytes.count))
            b += bytes
            let bits = Float(wh).bitPattern
            for s in stride(from: 0, to: 32, by: 8) { b.append(UInt8((bits >> UInt32(s)) & 0xFF)) }
        }
        return try (Data(b) as NSData).compressed(using: .lzfse) as Data
    }

    nonisolated private static func decodificar(_ dados: Data, inicio: Date) -> Dia? {
        guard let bruto = try? (dados as NSData).decompressed(using: .lzfse) as Data else { return nil }
        let b = [UInt8](bruto)
        var i = 0
        func u16() -> UInt16? {
            guard i + 2 <= b.count else { return nil }
            defer { i += 2 }
            return UInt16(b[i]) | UInt16(b[i + 1]) << 8
        }
        guard b.first == 1 else { return nil }
        i = 1
        guard let n = u16() else { return nil }
        var dia = Dia(inicio: inicio)
        dia.pontos.reserveCapacity(Int(n))
        for _ in 0..<Int(n) {
            guard let min = u16(), let pct = u16(), let rit = u16(), let w = u16(), i < b.count else { return nil }
            let flags = b[i]; i += 1
            dia.pontos.append(PontoMinuto(
                data: inicio.addingTimeInterval(Double(min) * 60), percentual: Double(pct) / 10,
                ritmo: Double(Int16(bitPattern: rit)) / 10, watts: Double(Int16(bitPattern: w)) / 10,
                naTomada: flags & 1 != 0, carregando: flags & 2 != 0))
        }
        if let nApps = u16() {
            for _ in 0..<Int(nApps) {
                guard i < b.count else { break }
                let len = Int(b[i]); i += 1
                guard i + len + 4 <= b.count else { break }
                let nome = String(decoding: b[i..<(i + len)], as: UTF8.self); i += len
                var bits: UInt32 = 0
                for k in 0..<4 { bits |= UInt32(b[i + k]) << UInt32(8 * k) }
                i += 4
                dia.apps[nome] = Double(Float(bitPattern: bits))
            }
        }
        return dia
    }
}

// MARK: - Exemplo (só para o modo --foto)

extension Historico {
    /// 30 dias sintéticos, em memória, parecidos com Detalhes.dc.html:
    /// de manhã 100% até ~11h, carga até 80%, descarga à tarde, carga à noite (às vezes parada em 80%).
    static func exemplo(agora fixo: Date? = nil, percentualAgora: Double? = nil) -> Historico {
        let h = Historico(dias: 90, emMemoria: true)
        let cal = Calendar.current
        let agora = fixo ?? Date()
        let hoje = cal.startOfDay(for: agora)
        var semente: UInt64 = 20261113
        func sorteio() -> Double {
            semente = semente &* 6364136223846793005 &+ 1442695040888963407
            return Double(semente >> 33) / Double(1 << 31)
        }
        let porRitmoW = 0.93      // W por 1 %/h descarregando
        let porCargaW = 1.87      // W por 1 %/h carregando
        var pct = 80.0
        let appsBase: [(String, Double)] = [
            ("Tela e sistema", 14.2), ("Claude", 12.6), ("Google Chrome", 9.8),
            ("Microsoft Teams", 7.1), ("Xcode", 4.4), ("Outros", 3.9),
        ]
        for d in stride(from: 29, through: 0, by: -1) {
            guard let inicio = cal.date(byAdding: .day, value: -d, to: hoje) else { continue }
            let r1 = -(6 + sorteio() * 8), r2 = -(6 + sorteio() * 8)
            let alvoNoite = sorteio() < 0.4 ? 80.0 : 100.0
            var dia = Dia(inicio: inicio)
            let fimDoDia = d == 0 ? Int(agora.timeIntervalSince(inicio) / 60) : 1440
            var fase = 0
            for m in 0..<fimDoDia {
                var ritmo = 0.0, tomada = true, carregando = false
                let hora = Double(m) / 60
                switch fase {
                case 0:   // parado na tomada até 08:05
                    if m >= 8 * 60 + 5 { fase = 1 }
                case 1:   // descarga da manhã até ~11:12
                    if hora >= 11.2 { fase = 2 }
                case 2:   // carga até 80%
                    if pct >= 80 { fase = 3 }
                case 3:   // descarga da tarde até ~18:30 ou 15%
                    if hora >= 18.5 || pct <= 15 { fase = 4 }
                case 4:   // carga da noite
                    if pct >= alvoNoite { fase = 5 }
                default: break
                }
                switch fase {
                case 1, 3:
                    ritmo = (fase == 1 ? r1 : r2) * (1 + 0.25 * sin(Double(m) / 23) + (sorteio() - 0.5) * 0.15)
                    tomada = false
                case 2, 4:
                    ritmo = 30 + sorteio() * 3
                    tomada = true; carregando = true
                default:
                    break
                }
                pct = min(alvoNoite == 80 && fase >= 5 ? 80 : 100, max(3, pct + ritmo / 60))
                let watts = ritmo < 0 ? ritmo * porRitmoW : (carregando ? ritmo * porCargaW : 0.3)
                dia.pontos.append(PontoMinuto(
                    data: inicio.addingTimeInterval(Double(m) * 60),
                    percentual: (pct * 10).rounded() / 10, ritmo: (ritmo * 10).rounded() / 10,
                    watts: (watts * 10).rounded() / 10, naTomada: tomada, carregando: carregando))
            }
            let escala = (0.75 + sorteio() * 0.5) * Double(fimDoDia) / 1440 * (d == 0 ? 1.6 : 1)
            for (nome, wh) in appsBase { dia.apps[nome] = ((wh * escala) * 10).rounded() / 10 }
            if d == 0, let alvo = percentualAgora, let ultimo = dia.pontos.last?.percentual {
                // Ajusta o trecho final de descarga para terminar no percentual da situação de exemplo.
                let delta = alvo - ultimo
                var ini = dia.pontos.count - 1
                while ini > 0, !dia.pontos[ini - 1].naTomada { ini -= 1 }
                let n = max(1, dia.pontos.count - 1 - ini)
                for k in ini..<dia.pontos.count {
                    dia.pontos[k].percentual = ((dia.pontos[k].percentual + delta * Double(k - ini + 1) / Double(n + 1)) * 10).rounded() / 10
                }
            }
            dia.alterado = true
            h.cache[inicio] = dia
        }
        return h
    }
}
