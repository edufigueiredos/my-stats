import Foundation

// Contrato dos módulos do sistema: só dados e formatos. Quem lê o sistema (CPU, GPU, memória, disco, rede, sensores)
// preenche estes tipos; painéis e itens da barra só os consomem. Valores de exemplo reproduzem docs/desenho/modulos/.

// MARK: - Módulos

enum Modulo: String, CaseIterable, Codable, Sendable, Identifiable {
    case cpu, gpu, memoria, disco, rede, sensores, calendario

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memoria: return "Memória"
        case .disco: return "Disco"
        case .rede: return "Rede"
        case .sensores: return "Sensores"
        case .calendario: return "Calendário"
        }
    }

    /// Título com a preposição e o artigo ("da CPU", "do Disco"), para frases como "Painel da CPU".
    var comArtigo: String {
        switch self {
        case .disco: return "do Disco"
        case .sensores: return "dos Sensores"
        case .calendario: return "do Calendário"
        default: return "da \(titulo)"
        }
    }

    /// Rótulo pequeno do item na barra.
    var rotuloCurto: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memoria: return "MEM"
        case .disco: return "SSD"
        case .rede: return "PING"
        case .sensores: return "CPU °C"
        case .calendario: return "DATA"
        }
    }

    /// O que o valor do item mostra por padrão.
    var dica: String {
        switch self {
        case .cpu: return "uso total"
        case .gpu: return "uso total"
        case .memoria: return "usada ou pressão"
        case .disco: return "ocupado ou leitura/escrita"
        case .rede: return "latência ou velocidade"
        case .sensores: return "temperatura e potência"
        case .calendario: return "data, hora e compromissos"
        }
    }

    /// Texto do botão grande no rodapé do painel.
    var tituloAbrirApp: String {
        switch self {
        case .cpu, .gpu, .memoria: return "Abrir Monitor de Atividade"
        case .disco: return "Abrir Utilitário de Disco"
        case .rede: return "Abrir ajustes de Rede"
        case .sensores: return "Ver todos os sensores"
        case .calendario: return "Abrir Calendário"
        }
    }

    /// App do sistema que o botão abre.
    var nomeApp: String {
        switch self {
        case .cpu, .gpu, .memoria, .sensores: return "Monitor de Atividade"
        case .disco: return "Utilitário de Disco"
        case .rede: return "Ajustes de Rede"
        case .calendario: return "Calendário"
        }
    }
}

// MARK: - Calendário

enum AutorizacaoCalendario: Sendable, Equatable {
    case naoPedida, negada, permitida
}

/// Um compromisso de hoje em diante. Só vive na memória: nada disto é gravado em disco nem vai para log.
struct Compromisso: Sendable, Equatable, Identifiable {
    var id: String
    var titulo: String
    var inicio: Date
    var fim: Date
    var diaInteiro: Bool
    /// Cor da agenda, "#RRGGBB".
    var corHex: String
    var local: String? = nil
}

struct LeituraCalendario: Sendable, Equatable {
    var autorizacao: AutorizacaoCalendario = .naoPedida
    var compromissos: [Compromisso] = []
}

// MARK: - Processos

/// Uma linha de "Quem mais usa". `valor`: CPU em % (100 = 1 núcleo); memória em bytes; disco, leitura em B/s;
/// GPU em %; rede, baixa em B/s. `valor2`: escrita (disco) ou sobe (rede) em B/s. `fracao`: 0...1 relativa ao maior.
struct ProcessoUso: Sendable, Equatable, Identifiable {
    var id: String
    var nome: String
    var valor: Double
    var valor2: Double? = nil
    var fracao: Double
}

/// nil = a seção fica escondida (GPU e rede por processo nem sempre dá para ler).
struct ProcessosModulos: Sendable, Equatable {
    var cpu: [ProcessoUso] = []
    var memoria: [ProcessoUso] = []
    var disco: [ProcessoUso] = []
    var gpu: [ProcessoUso]? = nil
    var rede: [ProcessoUso]? = nil
}

// MARK: - Leituras

struct LeituraCPU: Sendable, Equatable {
    /// Percentuais de 0 a 100.
    var uso: Double = 0
    var usuario: Double = 0
    var sistema: Double = 0
    /// Por núcleo: desempenho primeiro, depois eficiência.
    var nucleos: [Double] = []
    var nucleosDesempenho: Int = 0
    var nucleosEficiencia: Int = 0
    /// Nomes do sistema para os dois níveis (hw.perflevel0.name e hw.perflevel1.name), ex. "Super", "Performance", "Efficiency".
    var nomeNivel0: String? = nil
    var nomeNivel1: String? = nil
    /// Carga média de 1, 5 e 15 min.
    var cargaMedia: [Double] = []
    var processos: Int? = nil
    var threads: Int? = nil
}

struct TelaGPU: Sendable, Equatable {
    var nome: String
    var integrada: Bool
    var hz: Int? = nil
}

struct LeituraGPU: Sendable, Equatable {
    var uso: Double? = nil
    var memoriaEmUsoBytes: UInt64? = nil
    var nucleos: Int? = nil
    var nome: String? = nil
    var telas: [TelaGPU] = []
    var codificarVideo: Double? = nil
    var decodificarVideo: Double? = nil
}

enum PressaoMemoria: String, Sendable {
    case normal, aviso, critica

    var titulo: String {
        switch self {
        case .normal: return "Normal"
        case .aviso: return "Alta"
        case .critica: return "Crítica"
        }
    }
}

struct LeituraMemoria: Sendable, Equatable {
    var totalBytes: UInt64 = 0
    var appsBytes: UInt64 = 0
    var fixaBytes: UInt64 = 0
    var comprimidaBytes: UInt64 = 0
    var cacheBytes: UInt64 = 0
    var livreBytes: UInt64 = 0
    var swapUsadoBytes: UInt64 = 0
    var pressao: PressaoMemoria = .normal
    var pressaoPercentual: Double? = nil

    /// Apps + fixa + comprimida (o que o macOS não solta sem esforço).
    var usadaBytes: UInt64 { appsBytes + fixaBytes + comprimidaBytes }
    var usadaPercentual: Double {
        totalBytes == 0 ? 0 : min(100, Double(usadaBytes) / Double(totalBytes) * 100)
    }
}

struct VolumeDisco: Sendable, Equatable, Identifiable {
    var id: String
    var nome: String
    /// "SSD interno · APFS", "USB-C · ExFAT".
    var tipo: String
    var url: URL
    var totalBytes: UInt64
    var livreBytes: UInt64
    /// Espaço que o macOS libera sozinho se precisar.
    var purgavelBytes: UInt64 = 0
    var interno: Bool = true
    var ejetavel: Bool = false

    var ocupadoPercentual: Double {
        totalBytes == 0 ? 0 : min(100, Double(totalBytes - min(livreBytes, totalBytes)) / Double(totalBytes) * 100)
    }
}

struct SaudeSSD: Sendable, Equatable {
    var vidaUsadaPercentual: Double? = nil
    var gravadoBytes: UInt64? = nil
    var erros: Int? = nil
    var temperaturaC: Double? = nil
}

struct LeituraDisco: Sendable, Equatable {
    var volumes: [VolumeDisco] = []
    var leituraBps: Double = 0
    var escritaBps: Double = 0
    var saude: SaudeSSD? = nil
}

struct LeituraRede: Sendable, Equatable {
    var conectado: Bool = false
    /// "Wi-Fi", "Ethernet"...
    var tipo: String? = nil
    var nomeRede: String? = nil
    /// "5 GHz".
    var banda: String? = nil
    var baixandoBps: Double = 0
    var enviandoBps: Double = 0
    var hojeBaixadoBytes: UInt64? = nil
    var hojeEnviadoBytes: UInt64? = nil
    var latenciaMs: Double? = nil
    var variacaoMs: Double? = nil
    var perdaPercentual: Double? = nil
    var alvoLatencia: String = "1.1.1.1"
    var sinalDbm: Int? = nil
    var ruidoDbm: Int? = nil
    /// "149 · 80 MHz".
    var canal: String? = nil
    /// "Wi-Fi 6E".
    var padraoWiFi: String? = nil
    var velocidadeLinkMbps: Double? = nil
    var ipLocal: String? = nil
    var roteador: String? = nil
    var latenciaRoteadorMs: Double? = nil
    var dns: [String] = []
}

struct Temperatura: Sendable, Equatable, Identifiable {
    var id: String
    var nome: String
    var valorC: Double
}

struct Ventoinha: Sendable, Equatable, Identifiable {
    var id: Int
    var nome: String
    var rpm: Double
    var minimoRpm: Double? = nil
    var maximoRpm: Double? = nil

    /// Quanto da rotação máxima está em uso, 0...1.
    var fracao: Double? {
        guard let maximoRpm, maximoRpm > 0 else { return nil }
        return min(max(rpm / maximoRpm, 0), 1)
    }
}

struct LeituraSensores: Sendable, Equatable {
    var cpuC: Double? = nil
    var gpuC: Double? = nil
    var memoriaC: Double? = nil
    var ssdC: Double? = nil
    var bateriaC: Double? = nil
    var arC: Double? = nil
    var todas: [Temperatura] = []
    var ventoinhas: [Ventoinha] = []
    var sistemaW: Double? = nil
    var telaW: Double? = nil
    var carregadorW: Double? = nil
}

/// Potência e frequência por parte do chip (sem root, quando o sistema entrega).
struct EnergiaSoC: Sendable, Equatable {
    var cpuW: Double? = nil
    var gpuW: Double? = nil
    var aneW: Double? = nil
    var dramW: Double? = nil
    var gpuMHz: Double? = nil
    var gpuMaxMHz: Double? = nil
    /// % do intervalo com a GPU ligada (estados P do GPUPH), a mesma medida do iStat Menus.
    var gpuAtivo: Double? = nil
}

/// Tudo o que os módulos leem num instante. nil = módulo desligado ou sem leitura (a tela mostra "—").
struct LeiturasModulos: Sendable, Equatable {
    var data: Date
    var ligadoDesde: Date? = nil
    var cpu: LeituraCPU? = nil
    var gpu: LeituraGPU? = nil
    var memoria: LeituraMemoria? = nil
    var disco: LeituraDisco? = nil
    var rede: LeituraRede? = nil
    var sensores: LeituraSensores? = nil
    var energia: EnergiaSoC? = nil
    var calendario: LeituraCalendario? = nil
    var processos = ProcessosModulos()

    static let vazio = LeiturasModulos(data: Date(timeIntervalSince1970: 0))

    /// Dados dos desenhos (docs/desenho/modulos/), para o --foto e as prévias.
    static var exemplo: LeiturasModulos {
        let agora = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date()) ?? Date()
        let gib = 1024.0 * 1024 * 1024
        func mem(_ g: Double) -> UInt64 { UInt64((g * gib).rounded()) }
        func dec(_ g: Double) -> UInt64 { UInt64((g * 1e9).rounded()) }

        let cpu = LeituraCPU(
            uso: 83, usuario: 61, sistema: 22,
            nucleos: [98, 95, 92, 88, 97, 90, 86, 94, 91, 89, 85, 93, 52, 44, 49, 41],
            nucleosDesempenho: 12, nucleosEficiencia: 4,
            cargaMedia: [8.2, 7.4, 6.9], processos: 712, threads: 4380)
        let gpu = LeituraGPU(
            uso: 53, memoriaEmUsoBytes: mem(9.8), nucleos: 40, nome: "Apple GPU",
            telas: [TelaGPU(nome: "Integrada", integrada: true, hz: 120), TelaGPU(nome: "Externa", integrada: false, hz: 60)],
            codificarVideo: 30, decodificarVideo: 4)
        let memoria = LeituraMemoria(
            totalBytes: mem(48), appsBytes: mem(14.2), fixaBytes: mem(5.6), comprimidaBytes: mem(4.3),
            cacheBytes: mem(15.8), livreBytes: mem(8.1), swapUsadoBytes: mem(1.2),
            pressao: .normal, pressaoPercentual: 18)
        let disco = LeituraDisco(
            volumes: [
                VolumeDisco(id: "interno", nome: "Macintosh HD", tipo: "SSD interno · APFS", url: URL(fileURLWithPath: "/"),
                            totalBytes: dec(994), livreBytes: dec(557), purgavelBytes: dec(58), interno: true, ejetavel: false),
                VolumeDisco(id: "externo", nome: "SSD Externo", tipo: "USB-C · ExFAT", url: URL(fileURLWithPath: "/Volumes/SSD Externo"),
                            totalBytes: dec(2000), livreBytes: dec(580), purgavelBytes: 0, interno: false, ejetavel: true),
            ],
            leituraBps: 120e6, escritaBps: 8e6,
            saude: SaudeSSD(vidaUsadaPercentual: 2, gravadoBytes: dec(38_000), erros: 0, temperaturaC: 45))
        let rede = LeituraRede(
            conectado: true, tipo: "Wi-Fi", nomeRede: "Casa", banda: "5 GHz",
            baixandoBps: 12.4e6, enviandoBps: 820e3, hojeBaixadoBytes: dec(8.2), hojeEnviadoBytes: dec(1.1),
            latenciaMs: 6, variacaoMs: 1, perdaPercentual: 0, sinalDbm: -52, canal: "149 · 80 MHz", padraoWiFi: "Wi-Fi 6E",
            velocidadeLinkMbps: 1200, ipLocal: "192.168.0.12", roteador: "192.168.0.1", latenciaRoteadorMs: 2, dns: ["1.1.1.1"])
        let sensores = LeituraSensores(
            cpuC: 91, gpuC: 63, memoriaC: 52, ssdC: 45, bateriaC: 33, arC: 41,
            todas: [
                Temperatura(id: "cpu", nome: "CPU · média dos núcleos", valorC: 91),
                Temperatura(id: "gpu", nome: "GPU", valorC: 63),
                Temperatura(id: "memoria", nome: "Memória", valorC: 52),
                Temperatura(id: "ssd", nome: "SSD", valorC: 45),
                Temperatura(id: "bateria", nome: "Bateria", valorC: 33),
                Temperatura(id: "ar", nome: "Ar interno", valorC: 41),
            ],
            ventoinhas: [
                Ventoinha(id: 0, nome: "Esquerda", rpm: 4820, minimoRpm: 1200, maximoRpm: 5900),
                Ventoinha(id: 1, nome: "Direita", rpm: 4760, minimoRpm: 1200, maximoRpm: 5900),
            ],
            sistemaW: 100, telaW: 9, carregadorW: 140)
        let energia = EnergiaSoC(cpuW: 38, gpuW: 21, gpuMHz: 1180, gpuMaxMHz: 1440)
        let processos = ProcessosModulos(
            cpu: [
                ProcessoUso(id: "xcode", nome: "Xcode", valor: 212, fracao: 1),
                ProcessoUso(id: "swift-frontend", nome: "swift-frontend", valor: 148, fracao: 148 / 212),
                ProcessoUso(id: "chrome", nome: "Google Chrome", valor: 64, fracao: 64 / 212),
                ProcessoUso(id: "windowserver", nome: "WindowServer", valor: 22, fracao: 22 / 212),
            ],
            memoria: [
                ProcessoUso(id: "xcode", nome: "Xcode", valor: Double(mem(6.1)), fracao: 1),
                ProcessoUso(id: "chrome", nome: "Google Chrome", valor: Double(mem(4.8)), fracao: 4.8 / 6.1),
                ProcessoUso(id: "simulador", nome: "Simulador iOS", valor: Double(mem(2.7)), fracao: 2.7 / 6.1),
                ProcessoUso(id: "claude", nome: "Claude", valor: Double(mem(1.2)), fracao: 1.2 / 6.1),
                ProcessoUso(id: "kernel_task", nome: "kernel_task", valor: Double(mem(1.1)), fracao: 1.1 / 6.1),
            ],
            disco: [
                ProcessoUso(id: "spotlight", nome: "Spotlight", valor: 84e6, valor2: 1e6, fracao: 1),
                ProcessoUso(id: "xcode", nome: "Xcode", valor: 30e6, valor2: 6e6, fracao: 36 / 85),
                ProcessoUso(id: "timemachine", nome: "Time Machine", valor: 6e6, valor2: 0, fracao: 6 / 85),
            ],
            gpu: [
                ProcessoUso(id: "finalcut", nome: "Final Cut Pro", valor: 31, fracao: 1),
                ProcessoUso(id: "windowserver", nome: "WindowServer", valor: 14, fracao: 14 / 31),
                ProcessoUso(id: "chrome", nome: "Google Chrome", valor: 6, fracao: 6 / 31),
            ],
            rede: [
                ProcessoUso(id: "chrome", nome: "Google Chrome", valor: 9.8e6, valor2: 210e3, fracao: 1),
                ProcessoUso(id: "dropbox", nome: "Dropbox", valor: 2.1e6, valor2: 540e3, fracao: 2.1 / 9.8),
                ProcessoUso(id: "claude", nome: "Claude", valor: 120e3, valor2: 40e3, fracao: 0.12 / 9.8),
            ])
        return LeiturasModulos(
            data: agora, ligadoDesde: agora.addingTimeInterval(-(3 * 86_400 + 4 * 3_600)),
            cpu: cpu, gpu: gpu, memoria: memoria, disco: disco, rede: rede, sensores: sensores, energia: energia,
            calendario: calendarioExemplo(agora), processos: processos)
    }
}

extension LeiturasModulos {
    /// Compromissos fictícios (hoje e os dias seguintes) para o --foto.
    static func calendarioExemplo(_ agora: Date) -> LeituraCalendario {
        let cal = Calendar.current
        let hoje = cal.startOfDay(for: agora)
        func em(_ dias: Int, _ h: Int, _ min: Int = 0) -> Date {
            let d = cal.date(byAdding: .day, value: dias, to: hoje) ?? hoje
            return cal.date(bySettingHour: h, minute: min, second: 0, of: d) ?? d
        }
        func dia(_ dias: Int) -> (Date, Date) { (em(dias, 0), em(dias + 1, 0)) }
        let amanha = dia(1)
        let lista: [Compromisso] = [
            Compromisso(id: "a", titulo: "Reunião de equipe", inicio: em(0, 9), fim: em(0, 10), diaInteiro: false, corHex: "#4C8DF6"),
            Compromisso(id: "b", titulo: "Almoço", inicio: em(0, 12, 30), fim: em(0, 13, 30), diaInteiro: false, corHex: "#34C759"),
            Compromisso(id: "c", titulo: "Dentista", inicio: em(0, 16), fim: em(0, 17), diaInteiro: false, corHex: "#FF9F0A",
                        local: "Rua das Flores, 120"),
            Compromisso(id: "d", titulo: "Aniversário da Ana", inicio: amanha.0, fim: amanha.1, diaInteiro: true, corHex: "#AF52DE"),
            Compromisso(id: "e", titulo: "Revisão do projeto", inicio: em(2, 14), fim: em(2, 15, 30), diaInteiro: false, corHex: "#4C8DF6",
                        local: "Sala 3"),
            Compromisso(id: "f", titulo: "Academia", inicio: em(3, 7), fim: em(3, 8), diaInteiro: false, corHex: "#FF3B30"),
        ]
        return LeituraCalendario(autorizacao: .permitida, compromissos: lista)
    }
}

// MARK: - Formatos

extension Formato {
    /// Texto de "sem leitura".
    static let semDado = "—"

    /// Tira o ",0" final: "48 GB", mas "24,1 GB".
    private static func semZero(_ v: Double, casas: Int = 1) -> String {
        let t = numero(v, casas: casas)
        return t.hasSuffix(",0") ? String(t.dropLast(2)) : t
    }

    /// Memória em base 1024: "24,1 GB", "820 MB".
    static func bytesMemoria(_ bytes: UInt64) -> String {
        let b = Double(bytes)
        let k = 1024.0
        if b >= k * k * k * k { return semZero(b / (k * k * k * k)) + " TB" }
        if b >= k * k * k * 0.995 { return semZero(b / (k * k * k)) + " GB" }
        if b >= k * k { return numero(b / (k * k), casas: 0) + " MB" }
        return numero(b / k, casas: 0) + " KB"
    }

    /// Disco em base 1000, como o Finder: "437 GB", "1,4 TB", "38 TB".
    static func bytesDisco(_ bytes: UInt64) -> String {
        let b = Double(bytes)
        if b >= 1e12 {
            let t = b / 1e12
            return (t < 10 ? semZero(t) : numero(t, casas: 0)) + " TB"
        }
        if b >= 1e9 {
            let g = b / 1e9
            return (g < 10 ? semZero(g) : numero(g, casas: 0)) + " GB"
        }
        if b >= 1e6 { return numero(b / 1e6, casas: 0) + " MB" }
        return numero(b / 1e3, casas: 0) + " KB"
    }

    /// Velocidade de transferência: "12,4 MB/s", "120 MB/s", "8 MB/s", "820 KB/s", "0 KB/s".
    static func velocidade(_ bps: Double) -> String {
        let v = max(bps, 0)
        if v >= 999.5e3 {
            let mb = v / 1e6
            return (mb >= 99.95 ? numero(mb, casas: 0) : semZero(mb)) + " MB/s"
        }
        return numero(v / 1e3, casas: 0) + " KB/s"
    }

    /// "3 d 4 h", "5 h 12 min", "12 min".
    static func duracaoLonga(_ segundos: TimeInterval) -> String {
        let total = max(Int(segundos.rounded(.down)), 0)
        let d = total / 86_400, h = (total % 86_400) / 3_600, m = (total % 3_600) / 60
        if d > 0 { return h > 0 ? "\(d) d \(h) h" : "\(d) d" }
        if h > 0 { return m > 0 ? "\(h) h \(m) min" : "\(h) h" }
        return "\(m) min"
    }

    /// "91 °C" ou, na barra, "91°"; sem leitura vira "—".
    static func temperatura(_ c: Double?, curta: Bool) -> String {
        guard let c, c.isFinite else { return semDado }
        let n = numero(c, casas: 0)
        return curta ? n + "°" : n + " °C"
    }

    /// "4.820 rpm".
    static func rpm(_ v: Double) -> String { inteiro(Int(v.rounded())) + " rpm" }

    /// "6 ms".
    static func ms(_ v: Double) -> String { inteiro(Int(v.rounded())) + " ms" }
}
