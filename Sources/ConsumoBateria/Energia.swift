import Foundation
import IOKit
import IOKit.ps

/// Leituras extras de energia: temperatura, ciclos, carregador e modo de energia.
/// Cada chave que faltar vira nil; nada aqui força unwrap em valor do IOKit.
enum LeitorEnergia {
    static func ler() -> DetalhesEnergia {
        var detalhes = DetalhesEnergia.vazio
        detalhes.poucaEnergia = ProcessInfo.processInfo.isLowPowerModeEnabled
        lerAdaptador(em: &detalhes)
        lerCondicao(em: &detalhes)
        let modos = LeitorModoEnergia.atual()
        detalhes.modoEnergia = modos.atual
        detalhes.modoEnergiaBateria = modos.bateria
        detalhes.modoEnergiaTomada = modos.tomada
        detalhes.altoDesempenhoDisponivel = modos.altoDesempenho
        detalhes.aparelhosUSB = lerAparelhosUSB()

        let servico = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard servico != 0 else { return detalhes }
        defer { IOObjectRelease(servico) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(servico, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return detalhes }
        // Em alguns Macs as chaves só aparecem dentro de BatteryData.
        let dados = dict["BatteryData"] as? [String: Any] ?? [:]

        func inteiro(_ chave: String, em origem: [String: Any]? = nil) -> Int? {
            if let origem { return (origem[chave] as? NSNumber).map { Int($0.int64Value) } }
            if let n = dict[chave] as? NSNumber { return Int(n.int64Value) }
            if let n = dados[chave] as? NSNumber { return Int(n.int64Value) }
            return nil
        }
        func booleano(_ chave: String) -> Bool {
            (dict[chave] as? NSNumber)?.boolValue ?? (dict[chave] as? Bool) ?? false
        }

        // Temperatura em centésimos de °C (3050 = 30,5 °C). Valores absurdos (leitura inválida) viram nil.
        if let t = inteiro("Temperature") ?? inteiro("VirtualTemperature") {
            let graus = Double(t) / 100
            if graus > -20, graus < 120 { detalhes.temperaturaC = graus }
        }
        detalhes.ciclos = inteiro("CycleCount")
        if let ciclos = inteiro("DesignCycleCount9C"), ciclos > 0 { detalhes.ciclosProjeto = ciclos }
        // MaxCapacity vem em % no Apple Silicon; em mAh (valor grande) não serve como saúde.
        if let max = inteiro("MaxCapacity"), max > 0, max <= 100 { detalhes.saudeSistemaPercentual = max }
        if let fabrica = inteiro("DesignCapacity"), fabrica > 0 { detalhes.capacidadeFabricaMah = fabrica }

        // Entrada do sistema em mW; 0 ou ausente (sem tomada) vira nil.
        let telemetria = dict["PowerTelemetryData"] as? [String: Any]
        if let mw = inteiro("SystemPowerIn", em: telemetria), mw > 0 {
            detalhes.entradaSistemaW = Double(mw) / 1000
        }

        // Heurística de carga otimizada: na tomada, sem carregar e sem estar cheia (a bateria está sendo
        // segurada, por exemplo em 80%), ou o carregador informa um motivo para não carregar
        // (ChargerData/NotChargingReason diferente de 0).
        let naTomada = booleano("ExternalConnected")
        let segurada = naTomada && !booleano("IsCharging") && !booleano("FullyCharged")
        let dadosCarregador = dict["ChargerData"] as? [String: Any]
        let motivo = inteiro("NotChargingReason", em: dadosCarregador) ?? 0
        detalhes.cargaOtimizada = segurada || (naTomada && motivo != 0)

        // Energia saindo pelas portas USB: PowerOutDetails no topo ou dentro de BatteryData.
        let saidas = (dict["PowerOutDetails"] as? [[String: Any]]) ?? (dados["PowerOutDetails"] as? [[String: Any]]) ?? []
        detalhes.portasUSB = montarPortasUSB(saidas)

        return detalhes
    }

    // MARK: USB

    /// Estado das portas (AppleHPMInterfaceType10): número -> (conectada, transportes ativos).
    private static func lerEstadoPortas() -> [Int: (conectada: Bool, transportes: [String])] {
        var iterador: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleHPMInterfaceType10"), &iterador) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterador) }
        var estado: [Int: (conectada: Bool, transportes: [String])] = [:]
        while case let servico = IOIteratorNext(iterador), servico != 0 {
            defer { IOObjectRelease(servico) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(servico, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let d = props?.takeRetainedValue() as? [String: Any],
                  let numero = (d["PortNumber"] as? NSNumber)?.intValue else { continue }
            let ativa = (d["ConnectionActive"] as? NSNumber)?.boolValue ?? false
            let transportes = (d["TransportsActive"] as? [String]) ?? []
            estado[numero] = (ativa, transportes)
        }
        return estado
    }

    private static func montarPortasUSB(_ saidas: [[String: Any]]) -> [PortaUSB] {
        let estado = lerEstadoPortas()
        func n(_ d: [String: Any], _ k: String) -> Double? { (d[k] as? NSNumber)?.doubleValue }
        var portas: [PortaUSB] = []
        for item in saidas {
            guard let indice = n(item, "PortIndex").map({ Int($0) }) else { continue }
            let mw = n(item, "Watts") ?? 0
            let conectada = estado[indice]?.conectada ?? false
            guard mw > 0 || conectada else { continue }
            let mv = n(item, "ConfiguredVoltage").flatMap { $0 > 0 ? $0 : nil } ?? n(item, "AdapterVoltage").flatMap { $0 > 0 ? $0 : nil }
            let ma = n(item, "Current")
            let maximo = n(item, "PDPowermW").flatMap { $0 > 0 ? $0 / 1000 : nil }
            let comDados = (estado[indice]?.transportes ?? []).contains { $0 != "CC" }
            portas.append(PortaUSB(numero: indice, watts: mw / 1000, tensaoV: mv.map { $0 / 1000 },
                                   correnteA: ma.map { $0 / 1000 }, maximoCombinadoW: maximo, comDados: comDados))
        }
        return portas.sorted { $0.numero < $1.numero }
    }

    /// Aparelhos USB com dados (IOUSBHostDevice), sem hubs, sem nome e sem repetir.
    private static func lerAparelhosUSB() -> [String] {
        var iterador: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterador) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterador) }
        var nomes: [String] = []
        while case let servico = IOIteratorNext(iterador), servico != 0 {
            defer { IOObjectRelease(servico) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(servico, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let d = props?.takeRetainedValue() as? [String: Any] else { continue }
            let bruto = (d["USB Product Name"] as? String) ?? (d["kUSBProductString"] as? String) ?? ""
            let nome = bruto.trimmingCharacters(in: .whitespacesAndNewlines)
            let minusculo = nome.lowercased()
            guard !nome.isEmpty, !minusculo.contains("hub"), !minusculo.contains("internal"),
                  !nomes.contains(nome) else { continue }
            nomes.append(nome)
        }
        return nomes
    }

    /// BatteryHealth / BatteryHealthCondition da fonte interna, traduzidos.
    private static func lerCondicao(em detalhes: inout DetalhesEnergia) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let lista = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for fonte in lista {
            guard let desc = IOPSGetPowerSourceDescription(info, fonte)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let condicao = (desc["BatteryHealthCondition"] as? String) ?? ""
            let saude = (desc["BatteryHealth"] as? String) ?? ""
            let texto = condicao.isEmpty ? saude : condicao
            switch texto {
            case "", "Good": detalhes.condicao = "Normal"
            case "Check Battery", "Service Recommended": detalhes.condicao = "Manutenção recomendada"
            default: detalhes.condicao = texto
            }
            return
        }
    }

    private static func lerAdaptador(em detalhes: inout DetalhesEnergia) {
        guard let info = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else { return }
        if let w = info["Watts"] as? NSNumber, w.doubleValue > 0 { detalhes.adaptadorW = w.doubleValue }
        detalhes.adaptadorNome = (info["Name"] as? String) ?? (info["Description"] as? String)
    }
}

/// Modo de energia lido do pmset, no máximo uma vez a cada 60 s e fora da main thread.
/// Enquanto não há leitura (ou se o pmset falhar) vale ProcessInfo.isLowPowerModeEnabled.
enum LeitorModoEnergia {
    struct Modos: Sendable {
        var atual: ModoEnergia?
        var bateria: ModoEnergia?
        var tomada: ModoEnergia?
        /// `pmset -g cap` lista highpowermode.
        var altoDesempenho = false
    }

    private final class Cache: @unchecked Sendable {
        private let trava = NSLock()
        private var modos: Modos?
        private var ultima = Date.distantPast
        private var lendo = false

        /// Devolve o último valor e diz se é hora de renovar (marcando que há leitura em curso).
        func consultar() -> (Modos?, Bool) {
            trava.lock(); defer { trava.unlock() }
            let velho = Date().timeIntervalSince(ultima) >= 60
            let renovar = velho && !lendo
            if renovar { lendo = true }
            return (modos, renovar)
        }

        func guardar(_ novos: Modos?) {
            trava.lock(); defer { trava.unlock() }
            if let novos { modos = novos }
            ultima = Date()
            lendo = false
        }
    }

    private static let cache = Cache()

    /// Esquece o cache e relê agora (chamar fora da main thread).
    static func relerAgora() {
        cache.guardar(ler())
    }

    private static let capacidades = CapacidadesCache()

    private final class CapacidadesCache: @unchecked Sendable {
        private let trava = NSLock()
        private var valor: Bool?
        func obter(_ ler: () -> Bool?) -> Bool {
            trava.lock(); defer { trava.unlock() }
            if let valor { return valor }
            if let novo = ler() { valor = novo; return novo }
            return false
        }
    }

    static func atual() -> Modos {
        let (guardado, renovar) = cache.consultar()
        if renovar {
            DispatchQueue.global(qos: .utility).async { cache.guardar(ler()) }
        }
        if let guardado { return guardado }
        let baixa = ProcessInfo.processInfo.isLowPowerModeEnabled
        return Modos(atual: baixa ? .poucaEnergia : .automatico, bateria: nil, tomada: nil, altoDesempenho: false)
    }

    private static func ler() -> Modos? {
        guard let geral = rodarPmset(["-g"]), let custom = rodarPmset(["-g", "custom"]) else { return nil }
        let atual = valor(em: geral.components(separatedBy: "\n"))
        var secao: String?
        var linhas: [String: [String]] = [:]
        for linha in custom.components(separatedBy: "\n") {
            let t = linha.trimmingCharacters(in: .whitespaces)
            if t.hasSuffix("Power:") { secao = t; continue }
            if let secao { linhas[secao, default: []].append(linha) }
        }
        let bateria = valor(em: linhas["Battery Power:"] ?? [])
        let tomada = valor(em: linhas["AC Power:"] ?? [])
        guard atual != nil || bateria != nil || tomada != nil else { return nil }
        let alto = capacidades.obter { rodarPmset(["-g", "cap"]).map { $0.contains("highpowermode") } }
        return Modos(atual: atual ?? (ProcessInfo.processInfo.isLowPowerModeEnabled ? .poucaEnergia : .automatico),
                     bateria: bateria, tomada: tomada, altoDesempenho: alto)
    }

    /// "powermode N" (Apple Silicon e Macs recentes) ou "lowpowermode N" (Intel).
    private static func valor(em linhas: [String]) -> ModoEnergia? {
        var baixa: ModoEnergia?
        for linha in linhas {
            let partes = linha.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard partes.count >= 2, let n = Int(partes[1]) else { continue }
            switch partes[0] {
            case "powermode": return ModoEnergia(rawValue: n)
            case "lowpowermode": baixa = n == 1 ? .poucaEnergia : .automatico
            default: break
            }
        }
        return baixa
    }

    private static func rodarPmset(_ argumentos: [String]) -> String? {
        let processo = Process()
        processo.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        processo.arguments = argumentos
        let saida = Pipe()
        processo.standardOutput = saida
        processo.standardError = FileHandle.nullDevice
        do { try processo.run() } catch { return nil }
        let dados = saida.fileHandleForReading.readDataToEndOfFile()
        processo.waitUntilExit()
        guard processo.terminationStatus == 0 else { return nil }
        return String(data: dados, encoding: .utf8)
    }
}

/// Fonte de energia à qual o modo se aplica (-b bateria, -c tomada).
enum FonteEnergia: Sendable { case bateria, tomada }

/// Troca o modo de energia pedindo a senha de administrador ao próprio macOS (o app nunca vê a senha).
@MainActor
@Observable
final class ControleModoEnergia {
    static let compartilhado = ControleModoEnergia()

    private(set) var trocando: FonteEnergia?
    private(set) var erro: String?

    func trocar(_ fonte: FonteEnergia, para modo: ModoEnergia, depois: @escaping () -> Void) {
        guard trocando == nil else { return }
        trocando = fonte
        erro = nil
        Task { [weak self] in
            let resultado = await Task.detached(priority: .userInitiated) { () -> ResultadoTroca in
                let r = Self.executar(fonte, modo)
                if r == .ok { LeitorModoEnergia.relerAgora() }
                return r
            }.value
            guard let self else { return }
            self.trocando = nil
            switch resultado {
            case .ok: depois()
            case .cancelado: break
            case .falha(let m): self.erro = m
            }
        }
    }

    enum ResultadoTroca: Sendable, Equatable { case ok, cancelado, falha(String) }

    /// Roda o osascript com `do shell script ... with administrator privileges`; só entram números fixos no comando.
    nonisolated private static func executar(_ fonte: FonteEnergia, _ modo: ModoEnergia) -> ResultadoTroca {
        let opcao = fonte == .bateria ? "-b" : "-c"
        let script = "do shell script \"/usr/bin/pmset \(opcao) powermode \(modo.rawValue)\" with administrator privileges"
        let processo = Process()
        processo.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        processo.arguments = ["-e", script]
        let erro = Pipe()
        processo.standardOutput = FileHandle.nullDevice
        processo.standardError = erro
        do { try processo.run() } catch { return .falha("Não consegui trocar o modo.") }
        let texto = String(data: erro.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        processo.waitUntilExit()
        if processo.terminationStatus == 0 { return .ok }
        if texto.contains("-128") { return .cancelado }
        return .falha("Não consegui trocar o modo de energia.")
    }
}
