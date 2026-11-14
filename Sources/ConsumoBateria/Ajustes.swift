import Foundation
import Observation

/// Um aviso configurável: liga/desliga e limite.
struct Aviso: Codable, Sendable, Equatable {
    var ligado: Bool
    var limite: Double
}

/// Seções do painel da barra de menus (o cabeçalho é fixo e fica fora da lista).
enum SecaoPainel: String, CaseIterable, Codable, Sendable, Identifiable {
    case ritmoEAnel, blocos, grafico, quemMaisGasta, alimentacao, bateria, saude, modoEnergia, atalhos

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .ritmoEAnel: return "Ritmo e anel"
        case .blocos: return "Blocos"
        case .grafico: return "Gráfico"
        case .quemMaisGasta: return "Quem mais gasta"
        case .alimentacao: return "Alimentação"
        case .bateria: return "Bateria"
        case .saude: return "Saúde"
        case .modoEnergia: return "Modo de energia"
        case .atalhos: return "Atalhos"
        }
    }
}

/// Uma seção do painel na ordem do usuário, ligada ou não.
struct ItemSecaoPainel: Codable, Sendable, Equatable, Identifiable {
    var secao: SecaoPainel
    var ligada: Bool

    var id: String { secao.rawValue }

    /// Ordem padrão, tudo ligado.
    static var padrao: [ItemSecaoPainel] { SecaoPainel.allCases.map { ItemSecaoPainel(secao: $0, ligada: true) } }

    private struct Cru: Decodable {
        var secao: String
        var ligada: Bool?
    }

    /// Lê a lista gravada: ignora seção que o app não conhece mais, repetida, e acrescenta no fim
    /// (ligada) a que a config antiga não tinha. Sem dados, a ordem padrão.
    static func decodificar(_ dados: Data?) -> [ItemSecaoPainel] {
        guard let dados, let crus = try? JSONDecoder().decode([Cru].self, from: dados) else { return padrao }
        var lista: [ItemSecaoPainel] = []
        for c in crus {
            guard let s = SecaoPainel(rawValue: c.secao), !lista.contains(where: { $0.secao == s }) else { continue }
            lista.append(ItemSecaoPainel(secao: s, ligada: c.ligada ?? true))
        }
        for s in SecaoPainel.allCases where !lista.contains(where: { $0.secao == s }) {
            lista.append(ItemSecaoPainel(secao: s, ligada: true))
        }
        return lista
    }
}

/// O que o gráfico do painel mostra.
enum ModoGrafico: String, CaseIterable, Sendable {
    case ritmo, carga

    var titulo: String { self == .ritmo ? "Ritmo" : "Carga" }
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
        static let formatosSalvos = "formatosSalvos"
        static let avisoConsumo = "avisoConsumoAcima"
        static let avisoBateria = "avisoBateriaAbaixo"
        static let avisoCarregou = "avisoCarregouAte"
        static let avisoCarregador = "avisoCarregadorFraco"
        static let secoesPainel = "secoesPainel"
        static let modoGrafico = "modoGrafico"
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
    /// Formatos nomeados pelo usuário ("Meus formatos").
    var formatosSalvos: [FormatoSalvo] = [] { didSet { gravarJSON(formatosSalvos, Chave.formatosSalvos) } }
    /// Seções do painel, na ordem e com o liga/desliga do usuário.
    var secoesPainel: [ItemSecaoPainel] = ItemSecaoPainel.padrao { didSet { gravarJSON(secoesPainel, Chave.secoesPainel) } }
    var modoGrafico: ModoGrafico = .ritmo { didSet { gravar(modoGrafico.rawValue, Chave.modoGrafico) } }
    /// Não é gravado: quando existe, a barra real mostra este estado enquanto o usuário edita.
    var estadoEmPrevia: EstadoBarra? = nil

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
        secoesPainel = ItemSecaoPainel.decodificar(d.data(forKey: Chave.secoesPainel))
        if let s = d.string(forKey: Chave.modoGrafico), let v = ModoGrafico(rawValue: s) { modoGrafico = v }
        if let f = lerJSON([FormatoSalvo].self, Chave.formatosSalvos) { formatosSalvos = f }
        if let a = lerJSON(Aviso.self, Chave.avisoConsumo) { avisoConsumoAcima = a }
        if let a = lerJSON(Aviso.self, Chave.avisoBateria) { avisoBateriaAbaixo = a }
        if let a = lerJSON(Aviso.self, Chave.avisoCarregou) { avisoCarregouAte = a }
        if let a = lerJSON(Aviso.self, Chave.avisoCarregador) { avisoCarregadorFraco = a }
    }

    /// Peças e cor do estado (cai na predefinição se faltar).
    func config(_ estado: EstadoBarra) -> ConfigEstado {
        configs[estado] ?? formatoBarra.config(para: estado, corHex: estado.corPadraoHex)
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
            ($0, formato.config(para: $0, corHex: $0.corPadraoHex))
        })
    }

    // MARK: Seções do painel

    func alternarSecao(_ secao: SecaoPainel, ligada: Bool) {
        guard let i = secoesPainel.firstIndex(where: { $0.secao == secao }) else { return }
        secoesPainel[i].ligada = ligada
    }

    /// Move uma seção uma casa para cima (-1) ou para baixo (+1).
    func moverSecao(_ secao: SecaoPainel, _ delta: Int) {
        guard let i = secoesPainel.firstIndex(where: { $0.secao == secao }) else { return }
        let j = i + delta
        guard secoesPainel.indices.contains(j) else { return }
        secoesPainel.swapAt(i, j)
    }

    func restaurarOrdemPainel() { secoesPainel = ItemSecaoPainel.padrao }

    // MARK: Montagem e formatos do usuário

    /// Volta o estado à predefinição do formato escolhido, mantendo a cor que o usuário escolheu (como `aplicar(_:)`).
    func restaurarPredefinicao(_ estado: EstadoBarra) {
        configs[estado] = formatoBarra.config(para: estado, corHex: config(estado).corHex)
    }

    /// Copia a montagem de um estado para outros (cada destino mantém a sua cor e as suas faixas).
    func copiarMontagem(de origem: EstadoBarra, para destinos: [EstadoBarra]) {
        let fonte = config(origem)
        var novo = configs
        for d in destinos where d != origem {
            novo[d] = config(d).copiandoMontagem(de: fonte)
        }
        configs = novo
    }

    private func configsPorNome() -> [String: ConfigEstado] {
        Dictionary(uniqueKeysWithValues: EstadoBarra.allCases.map { ($0.rawValue, config($0)) })
    }

    nonisolated static let maximoSalvos = 50

    /// Salva a montagem atual. Devolve uma mensagem de recusa (nada é apagado) ou nil se salvou.
    @discardableResult
    func salvarFormatoAtual(nome: String) -> String? {
        guard formatosSalvos.count < Self.maximoSalvos else {
            return "Você já tem \(Self.maximoSalvos) formatos salvos. Apague algum para salvar outro."
        }
        var limpo = String(nome.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        if limpo.isEmpty { limpo = "Meu formato \(formatosSalvos.count + 1)" }
        let f = FormatoSalvo(nome: limpo, configs: configsPorNome().mapValues { $0.comNovosIds() })
        formatosSalvos.append(f)
        return nil
    }

    /// Aplica só os estados que o formato traz.
    func aplicarSalvo(_ f: FormatoSalvo) {
        var novo = configs
        for e in EstadoBarra.allCases {
            if let c = f.config(e) { novo[e] = c.saneado().comNovosIds() }
        }
        configs = novo
    }

    func apagarSalvo(id: UUID) {
        formatosSalvos.removeAll { $0.id == id }
    }

    func renomearSalvo(id: UUID, nome: String) {
        guard let i = formatosSalvos.firstIndex(where: { $0.id == id }) else { return }
        let limpo = String(nome.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        if !limpo.isEmpty { formatosSalvos[i].nome = limpo }
    }

    /// JSON dos formatos dados; nil exporta a montagem atual como "Montagem atual".
    func exportarJSON(_ formatos: [FormatoSalvo]? = nil) throws -> Data {
        let lista = formatos ?? [FormatoSalvo(nome: "Montagem atual", configs: configsPorNome())]
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(PacoteFormatos(formatos: lista))
    }

    enum ErroImportacao: LocalizedError {
        case grandeDemais, formatoDesconhecido, vazio, corInvalida(String), semEspaco

        var errorDescription: String? {
            switch self {
            case .grandeDemais: return "O arquivo passa de 512 KB."
            case .formatoDesconhecido: return "Não reconheci este arquivo como formatos do Consumo Bateria."
            case .vazio: return "O arquivo não traz nenhum estado que o app conheça."
            case .semEspaco: return "Você já tem \(Ajustes.maximoSalvos) formatos salvos. Apague algum para importar."
            case .corInvalida(let h): return "A cor \"\(h)\" não é válida (use #RRGGBB)."
            }
        }
    }

    struct ResultadoImportacao {
        var importados: [FormatoSalvo]
        /// Mensagem pt-BR pronta para mostrar ao usuário.
        var mensagem: String
    }

    /// Lê um arquivo de formatos e o acrescenta aos salvos (só o que cabe, sem apagar nada); não aplica nada sozinho.
    @discardableResult
    func importarJSON(_ dados: Data) throws -> ResultadoImportacao {
        guard dados.count <= 512 * 1024 else { throw ErroImportacao.grandeDemais }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let lidos: [FormatoSalvo]
        if let p = try? dec.decode(PacoteFormatos.self, from: dados) {
            lidos = p.formatos
        } else if let f = try? dec.decode(FormatoSalvo.self, from: dados) {
            lidos = [f]
        } else if let m = try? dec.decode([String: ConfigEstado].self, from: dados) {
            lidos = [FormatoSalvo(nome: "Importado", configs: m)]
        } else {
            throw ErroImportacao.formatoDesconhecido
        }
        for f in lidos {
            for (k, c) in f.configs where EstadoBarra(rawValue: k) != nil {
                var cores = [c.corHex] + [c.corFundoHex].compactMap { $0 }
                for i in c.pecas + c.pecasBaixo { if let h = i.corHex { cores.append(h) } }
                cores += c.faixas.map(\.corHex)
                if let ruim = cores.first(where: { !ConfigEstado.hexValido($0) }) { throw ErroImportacao.corInvalida(ruim) }
            }
        }
        var novos: [FormatoSalvo] = []
        for f in lidos {
            var cfgs: [String: ConfigEstado] = [:]
            for (k, v) in f.configs where EstadoBarra(rawValue: k) != nil {
                cfgs[k] = v.saneado().comNovosIds()
            }
            guard !cfgs.isEmpty else { continue }
            var n = FormatoSalvo(nome: String(f.nome.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)), configs: cfgs)
            if n.nome.isEmpty { n.nome = "Importado" }
            n.criadoEm = f.criadoEm
            novos.append(n)
        }
        guard !novos.isEmpty else { throw ErroImportacao.vazio }
        let cabem = Self.maximoSalvos - formatosSalvos.count
        guard cabem > 0 else { throw ErroImportacao.semEspaco }
        let aceitos = Array(novos.prefix(cabem))
        formatosSalvos.append(contentsOf: aceitos)
        let mensagem: String
        if aceitos.count < novos.count {
            mensagem = "Só cabem mais \(cabem) formatos; importei \(aceitos.count) de \(novos.count)."
        } else {
            mensagem = aceitos.count == 1 ? "1 formato importado" : "\(aceitos.count) formatos importados"
        }
        return ResultadoImportacao(importados: aceitos, mensagem: mensagem)
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
