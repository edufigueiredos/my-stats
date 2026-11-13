import Foundation
import Observation

/// Um aviso configurável: liga/desliga e limite.
struct Aviso: Codable, Sendable, Equatable {
    var ligado: Bool
    var limite: Double
}

/// Preferências do app, gravadas no UserDefaults a cada mudança.
/// Com `persistir: false` (modo --foto) é volátil e só usa os padrões.
@MainActor
@Observable
final class Ajustes {
    static let compartilhado = Ajustes()

    /// Chaves lidas direto pelo @AppStorage do tema.
    nonisolated static let chaveTema = "tema"
    nonisolated static let chaveCorNeon = "corNeonHex"

    private enum Chave {
        static let formato = "formatoBarra"
        static let configs = "configsEstado"
        static let media = "mediaRitmo"
        static let casas = "casasDecimais"
        static let sentido = "sentidoRitmo"
        static let colorir = "colorirBarra"
        static let limiteAlto = "limiteAlto"
        static let dias = "diasHistorico"
        static let avisoConsumo = "avisoConsumoAcima"
        static let avisoBateria = "avisoBateriaAbaixo"
        static let avisoCarregou = "avisoCarregouAte"
        static let avisoCarregador = "avisoCarregadorFraco"
    }

    @ObservationIgnored private let persistir: Bool
    @ObservationIgnored private let defaults = UserDefaults.standard

    var formatoBarra: FormatoBarra = .empilhado { didSet { gravar(formatoBarra.rawValue, Chave.formato) } }
    var configs: [EstadoBarra: ConfigEstado] = Ajustes.configsPadrao(.empilhado) { didSet { gravarConfigs() } }
    var mediaRitmo: MediaRitmo = .quinzeMin { didSet { gravar(mediaRitmo.rawValue, Chave.media) } }
    var casasDecimais: Int = 1 { didSet { gravar(casasDecimais, Chave.casas) } }
    var sentido: SentidoRitmo = .sinais { didSet { gravar(sentido.rawValue, Chave.sentido) } }
    var colorirBarra = true { didSet { gravar(colorirBarra, Chave.colorir) } }
    /// Acima deste ritmo (%/h, em módulo) o estado vira "consumo alto".
    var limiteAlto: Double = 20 { didSet { gravar(limiteAlto, Chave.limiteAlto) } }
    var diasHistorico: Int = 90 { didSet { gravar(diasHistorico, Chave.dias) } }

    var avisoConsumoAcima = Aviso(ligado: true, limite: 20) { didSet { gravarJSON(avisoConsumoAcima, Chave.avisoConsumo) } }
    var avisoBateriaAbaixo = Aviso(ligado: true, limite: 20) { didSet { gravarJSON(avisoBateriaAbaixo, Chave.avisoBateria) } }
    var avisoCarregouAte = Aviso(ligado: false, limite: 80) { didSet { gravarJSON(avisoCarregouAte, Chave.avisoCarregou) } }
    var avisoCarregadorFraco = Aviso(ligado: true, limite: 30) { didSet { gravarJSON(avisoCarregadorFraco, Chave.avisoCarregador) } }

    init(persistir: Bool = true) {
        self.persistir = persistir
        guard persistir else { return }
        let d = defaults
        if let s = d.string(forKey: Chave.formato), let v = FormatoBarra(rawValue: s) { formatoBarra = v }
        if let dados = d.data(forKey: Chave.configs),
           let lidos = try? JSONDecoder().decode([String: ConfigEstado].self, from: dados) {
            var c = Ajustes.configsPadrao(formatoBarra)
            for (k, v) in lidos { if let e = EstadoBarra(rawValue: k) { c[e] = v } }
            configs = c
        } else {
            configs = Ajustes.configsPadrao(formatoBarra)
        }
        if let s = d.string(forKey: Chave.media), let v = MediaRitmo(rawValue: s) { mediaRitmo = v }
        if d.object(forKey: Chave.casas) != nil { casasDecimais = d.integer(forKey: Chave.casas) }
        if let s = d.string(forKey: Chave.sentido), let v = SentidoRitmo(rawValue: s) { sentido = v }
        if d.object(forKey: Chave.colorir) != nil { colorirBarra = d.bool(forKey: Chave.colorir) }
        if d.object(forKey: Chave.limiteAlto) != nil { limiteAlto = d.double(forKey: Chave.limiteAlto) }
        if d.object(forKey: Chave.dias) != nil { diasHistorico = d.integer(forKey: Chave.dias) }
        if let a = lerJSON(Aviso.self, Chave.avisoConsumo) { avisoConsumoAcima = a }
        if let a = lerJSON(Aviso.self, Chave.avisoBateria) { avisoBateriaAbaixo = a }
        if let a = lerJSON(Aviso.self, Chave.avisoCarregou) { avisoCarregouAte = a }
        if let a = lerJSON(Aviso.self, Chave.avisoCarregador) { avisoCarregadorFraco = a }
    }

    /// Peças e cor do estado (cai na predefinição se faltar).
    func config(_ estado: EstadoBarra) -> ConfigEstado {
        configs[estado] ?? ConfigEstado(pecas: formatoBarra.pecas(para: estado), corHex: estado.corPadraoHex)
    }

    /// Escolhe um formato pronto: reescreve as listas de peças de todos os estados, mantendo as cores.
    func aplicar(_ formato: FormatoBarra) {
        let cores = configs.mapValues(\.corHex)
        var novo = Ajustes.configsPadrao(formato)
        for e in EstadoBarra.allCases {
            if let cor = cores[e] { novo[e]?.corHex = cor }
        }
        formatoBarra = formato
        configs = novo
    }

    static func configsPadrao(_ formato: FormatoBarra) -> [EstadoBarra: ConfigEstado] {
        Dictionary(uniqueKeysWithValues: EstadoBarra.allCases.map {
            ($0, ConfigEstado(pecas: formato.pecas(para: $0), corHex: $0.corPadraoHex))
        })
    }

    // MARK: Gravação

    private func gravar(_ valor: Any, _ chave: String) {
        guard persistir else { return }
        defaults.set(valor, forKey: chave)
    }

    private func gravarJSON<T: Encodable>(_ valor: T, _ chave: String) {
        guard persistir, let dados = try? JSONEncoder().encode(valor) else { return }
        defaults.set(dados, forKey: chave)
    }

    private func lerJSON<T: Decodable>(_ tipo: T.Type, _ chave: String) -> T? {
        guard let dados = defaults.data(forKey: chave) else { return nil }
        return try? JSONDecoder().decode(tipo, from: dados)
    }

    private func gravarConfigs() {
        gravarJSON(Dictionary(uniqueKeysWithValues: configs.map { ($0.key.rawValue, $0.value) }), Chave.configs)
    }
}
