import Foundation
import SwiftUI

// MARK: - Estados, peças e formatos da barra

/// Os cinco estados que a barra de menus distingue; cada um tem a sua lista de peças e a sua cor.
enum EstadoBarra: String, CaseIterable, Codable, Sendable, Identifiable {
    case cheia, carregando, descarregando, parado, alto

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .cheia: return "Cheia"
        case .carregando: return "Carregando"
        case .descarregando: return "Descarregando"
        case .parado: return "Na tomada, parado"
        case .alto: return "Consumo alto"
        }
    }

    /// Frase curta do desenho (Preferencias.dc.html) sob o nome do estado.
    var dica: String {
        switch self {
        case .cheia: return "na tomada, 100%"
        case .carregando: return "entrando energia"
        case .descarregando: return "na bateria"
        case .parado: return "carga otimizada"
        case .alto: return "acima do aviso"
        }
    }

    var corPadraoHex: String {
        switch self {
        case .cheia: return "#34C759"
        case .carregando: return "#E0B357"
        case .descarregando: return "#FFFFFF"
        case .parado: return "#BF5AF2"
        case .alto: return "#FF9F0A"
        }
    }
}

/// As 18 peças que se combinam na barra, na ordem da paleta do desenho.
enum Peca: String, CaseIterable, Codable, Sendable, Identifiable {
    case ritmo, ritmoWatts, ritmoSobreBateria, tempoSobreBateria, porcentagem, tempo, horario, watts
    case etiquetaValor, texto, icone, bateria, barraVertical, anel, velocimetro, numeroPilula, espacador, separador

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .ritmo: return "Ritmo %/h"
        case .ritmoWatts: return "Ritmo, %, watts e tempo"
        case .ritmoSobreBateria: return "Ritmo sobre a bateria"
        case .tempoSobreBateria: return "Tempo sobre a bateria"
        case .porcentagem: return "Porcentagem"
        case .tempo: return "Tempo"
        case .horario: return "Horário"
        case .watts: return "Watts"
        case .etiquetaValor: return "Etiqueta e valor"
        case .texto: return "Texto livre"
        case .icone: return "Ícone"
        case .bateria: return "Bateria"
        case .barraVertical: return "Barra vertical"
        case .anel: return "Anel"
        case .velocimetro: return "Velocímetro"
        case .numeroPilula: return "Número na pílula"
        case .espacador: return "Espaçador"
        case .separador: return "Separador ·"
        }
    }

    /// Nome de SF Symbol para a paleta de peças.
    var simbolo: String {
        switch self {
        case .ritmo: return "gauge.with.dots.needle.33percent"
        case .ritmoWatts: return "text.justify.leading"
        case .ritmoSobreBateria: return "battery.50percent"
        case .tempoSobreBateria: return "clock.badge"
        case .porcentagem: return "percent"
        case .tempo: return "clock"
        case .horario: return "clock.badge.checkmark"
        case .watts: return "bolt"
        case .etiquetaValor: return "tag"
        case .texto: return "character.cursor.ibeam"
        case .icone: return "arrow.down.circle"
        case .bateria: return "battery.75percent"
        case .barraVertical: return "chart.bar.fill"
        case .anel: return "circle.dotted"
        case .velocimetro: return "gauge.with.needle"
        case .numeroPilula: return "capsule"
        case .espacador: return "arrow.left.and.right"
        case .separador: return "circle.fill"
        }
    }
}

/// Os formatos prontos do item da barra; cada um é uma predefinição das listas de peças.
enum FormatoBarra: String, CaseIterable, Codable, Sendable, Identifiable {
    case empilhado, icone, valor, iconeValor, duasLinhas, velocimetro

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .empilhado: return "Empilhado"
        case .icone: return "Ícone"
        case .valor: return "Valor"
        case .iconeValor: return "Ícone + valor"
        case .duasLinhas: return "Duas linhas"
        case .velocimetro: return "Velocímetro"
        }
    }

    var descricao: String {
        switch self {
        case .empilhado: return "Igual ao seu iStat: valor grande, tempo pequeno em cima da bateria. Monte o seu nas preferências."
        case .icone: return "A bateria enche com o %; seta, raio ou tomada dizem o que está acontecendo."
        case .valor: return "Só o ritmo em %/h, sem desenho."
        case .iconeValor: return "Bateria e ritmo lado a lado."
        case .duasLinhas: return "Ritmo e % em cima; watts e tempo embaixo, como o iStat."
        case .velocimetro: return "O ponteiro sobe conforme o gasto; carregando vira raio."
        }
    }

    /// Lista de peças do formato em cada estado.
    /// Parado e cheia não têm ritmo: o Empilhado mostra "80%" e "tomada" (peça Tempo sobre a bateria).
    func pecas(para estado: EstadoBarra) -> [ItemPeca] {
        let semRitmo = estado == .parado || estado == .cheia
        let lista: [Peca]
        switch self {
        case .empilhado: lista = semRitmo ? [.porcentagem, .tempoSobreBateria] : [.ritmo, .tempoSobreBateria]
        case .icone: lista = [.bateria]
        case .valor: lista = semRitmo ? [.porcentagem] : [.ritmo]
        case .iconeValor: lista = semRitmo ? [.bateria, .porcentagem] : [.bateria, .ritmo]
        case .duasLinhas: lista = semRitmo ? [.porcentagem] : [.ritmo, .separador, .porcentagem]
        case .velocimetro: lista = [.velocimetro, semRitmo ? .porcentagem : .ritmo]
        }
        return lista.map { ItemPeca($0) }
    }

    /// Linha de baixo do formato (vazia = uma linha só). Só o Duas linhas usa.
    func pecasBaixo(para estado: EstadoBarra) -> [ItemPeca] {
        let semRitmo = estado == .parado || estado == .cheia
        switch self {
        case .duasLinhas: return (semRitmo ? [.tempo] : [.watts, .separador, .tempo]).map { ItemPeca($0) }
        default: return []
        }
    }

    /// Predefinição completa do estado, com a cor dada.
    func config(para estado: EstadoBarra, corHex: String) -> ConfigEstado {
        ConfigEstado(pecas: pecas(para: estado), pecasBaixo: pecasBaixo(para: estado), corHex: corHex)
    }
}

/// Qual das duas linhas do item.
enum LinhaPeca: Sendable {
    case cima, baixo
}

/// Alinhamento horizontal de uma linha do item (visível quando as duas linhas têm larguras diferentes).
enum AlinhamentoLinha: String, CaseIterable, Codable, Sendable, Identifiable {
    case esquerda, centro, direita

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .esquerda: return "Esquerda"
        case .centro: return "Centro"
        case .direita: return "Direita"
        }
    }

    var simbolo: String {
        switch self {
        case .esquerda: return "text.alignleft"
        case .centro: return "text.aligncenter"
        case .direita: return "text.alignright"
        }
    }

    var horizontal: HorizontalAlignment {
        switch self {
        case .esquerda: return .leading
        case .centro: return .center
        case .direita: return .trailing
        }
    }

    var alinhamento: Alignment {
        switch self {
        case .esquerda: return .leading
        case .centro: return .center
        case .direita: return .trailing
        }
    }
}

/// Como o tempo restante aparece nas peças de tempo.
enum FormatoTempo: String, CaseIterable, Codable, Sendable, Identifiable {
    case relogio, horasMinutos, horarioFim, minutos

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .relogio: return "4:46"
        case .horasMinutos: return "4h46"
        case .horarioFim: return "Horário"
        case .minutos: return "Minutos"
        }
    }
}

/// Família da fonte do item inteiro.
enum FonteItem: String, CaseIterable, Codable, Sendable, Identifiable {
    case padrao, arredondada, monoespacada, serifada

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .padrao: return "Padrão"
        case .arredondada: return "Arredondada"
        case .monoespacada: return "Mono"
        case .serifada: return "Serifada"
        }
    }

    var design: Font.Design {
        switch self {
        case .padrao: return .default
        case .arredondada: return .rounded
        case .monoespacada: return .monospaced
        case .serifada: return .serif
        }
    }
}

/// Alinhamento das peças dentro de uma linha, no eixo vertical.
enum AlinhamentoVertical: String, CaseIterable, Codable, Sendable, Identifiable {
    case topo, centro, base

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .topo: return "Topo"
        case .centro: return "Centro"
        case .base: return "Base"
        }
    }

    var simbolo: String {
        switch self {
        case .topo: return "align.vertical.top"
        case .centro: return "align.vertical.center"
        case .base: return "align.vertical.bottom"
        }
    }

    var vertical: VerticalAlignment {
        switch self {
        case .topo: return .top
        case .centro: return .center
        case .base: return .bottom
        }
    }
}

/// Fundo desenhado atrás do item.
enum FundoItem: String, CaseIterable, Codable, Sendable, Identifiable {
    case nenhum, pilula, contorno

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .nenhum: return "Nenhum"
        case .pilula: return "Pílula"
        case .contorno: return "Contorno"
        }
    }
}

/// O que a faixa de cor mede.
enum MedidaFaixa: String, CaseIterable, Codable, Sendable, Identifiable {
    case ritmo, porcentagem

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .ritmo: return "Ritmo %/h"
        case .porcentagem: return "Carga %"
        }
    }
}

enum ComparacaoFaixa: String, CaseIterable, Codable, Sendable, Identifiable {
    case acimaDe, abaixoDe

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .acimaDe: return "acima de"
        case .abaixoDe: return "abaixo de"
        }
    }
}

/// Regra "se a medida passar do limite, o item usa esta cor".
struct FaixaCor: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var medida: MedidaFaixa
    var comparacao: ComparacaoFaixa
    var limite: Double
    var corHex: String

    init(medida: MedidaFaixa, comparacao: ComparacaoFaixa, limite: Double, corHex: String) {
        self.id = UUID()
        self.medida = medida
        self.comparacao = comparacao
        self.limite = limite
        self.corHex = corHex
    }

    private enum CodingKeys: String, CodingKey { case id, medida, comparacao, limite, corHex }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        medida = try c.decode(MedidaFaixa.self, forKey: .medida)
        comparacao = try c.decode(ComparacaoFaixa.self, forKey: .comparacao)
        limite = try c.decode(Double.self, forKey: .limite)
        corHex = try c.decode(String.self, forKey: .corHex)
    }

    func vale(para s: Situacao) -> Bool {
        let valor: Double
        switch medida {
        case .ritmo: valor = abs(s.ritmoMedio ?? s.ritmoAgora)
        case .porcentagem: valor = Double(s.leitura.percentual)
        }
        return comparacao == .acimaDe ? valor > limite : valor < limite
    }
}

/// Uma peça colocada no item, com os ajustes dela. nil = automático (vem da linha ou do estado).
struct ItemPeca: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var peca: Peca
    /// Tamanho do texto em pt (7...16); os desenhos escalam junto. nil = o da linha.
    var tamanho: Double?
    var negrito: Bool?
    /// Cor própria; nil = a cor do estado.
    var corHex: String?
    /// Deslocamento vertical em pt (−3...+3); positivo sobe.
    var deslocamentoY: Double?
    /// Modelo da peça Texto livre (com marcadores) ou etiqueta da Etiqueta e valor.
    var texto: String?
    var prefixo: String?
    var sufixo: String?
    /// Casas decimais (0...2); nil = a global.
    var casas: Int?
    /// nil = mostra a unidade.
    var unidade: Bool?
    /// nil = o sentido global.
    var sentido: SentidoRitmo?
    var formatoTempo: FormatoTempo?
    /// SF Symbol da peça Ícone; nil = o desenho do estado.
    var simbolo: String?

    static let limiteTexto = 40

    static let simbolosIcone: [String] = [
        "bolt.fill", "battery.100percent", "battery.25percent", "powerplug.fill",
        "leaf.fill", "flame.fill", "gauge.with.needle", "arrow.down",
        "arrow.up", "arrow.down.circle", "heart.fill", "sun.max.fill",
        "moon.fill", "cpu", "laptopcomputer", "hourglass",
    ]

    init(_ peca: Peca, tamanho: Double? = nil, negrito: Bool? = nil, corHex: String? = nil, deslocamentoY: Double? = nil,
         texto: String? = nil, prefixo: String? = nil, sufixo: String? = nil, casas: Int? = nil,
         unidade: Bool? = nil, sentido: SentidoRitmo? = nil, formatoTempo: FormatoTempo? = nil, simbolo: String? = nil) {
        self.id = UUID()
        self.peca = peca
        self.tamanho = tamanho
        self.negrito = negrito
        self.corHex = corHex
        self.deslocamentoY = deslocamentoY
        self.texto = texto
        self.prefixo = prefixo
        self.sufixo = sufixo
        self.casas = casas
        self.unidade = unidade
        self.sentido = sentido
        self.formatoTempo = formatoTempo
        self.simbolo = simbolo
    }

    private enum CodingKeys: String, CodingKey {
        case id, peca, tamanho, negrito, corHex, deslocamentoY
        case texto, prefixo, sufixo, casas, unidade, sentido, formatoTempo, simbolo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        peca = try c.decode(Peca.self, forKey: .peca)
        tamanho = try c.decodeIfPresent(Double.self, forKey: .tamanho)
        negrito = try c.decodeIfPresent(Bool.self, forKey: .negrito)
        corHex = try c.decodeIfPresent(String.self, forKey: .corHex)
        deslocamentoY = try c.decodeIfPresent(Double.self, forKey: .deslocamentoY)
        texto = try c.decodeIfPresent(String.self, forKey: .texto)
        prefixo = try c.decodeIfPresent(String.self, forKey: .prefixo)
        sufixo = try c.decodeIfPresent(String.self, forKey: .sufixo)
        casas = try c.decodeIfPresent(Int.self, forKey: .casas)
        unidade = try c.decodeIfPresent(Bool.self, forKey: .unidade)
        sentido = try c.decodeIfPresent(SentidoRitmo.self, forKey: .sentido)
        formatoTempo = try c.decodeIfPresent(FormatoTempo.self, forKey: .formatoTempo)
        simbolo = try c.decodeIfPresent(String.self, forKey: .simbolo)
    }

    /// Algum ajuste fora do automático (o texto só conta fora da peça Texto livre).
    var personalizado: Bool {
        tamanho != nil || negrito != nil || corHex != nil || (deslocamentoY ?? 0) != 0
            || (peca != .texto && texto != nil) || prefixo != nil || sufixo != nil
            || casas != nil || unidade != nil || sentido != nil || formatoTempo != nil || simbolo != nil
    }

    /// Cópia com identificador novo (para colar em outro estado ou importar).
    func comNovoId() -> ItemPeca {
        var c = self
        c.id = UUID()
        return c
    }
}

/// Peças e cor de um estado.
struct ConfigEstado: Codable, Sendable, Equatable {
    var pecas: [ItemPeca]
    /// Linha de baixo; vazia = o item tem uma linha só.
    var pecasBaixo: [ItemPeca]
    var corHex: String
    var alinhamentoCima: AlinhamentoLinha
    var alinhamentoBaixo: AlinhamentoLinha
    /// Espaço entre as duas linhas, em pt (−2...+4). O padrão é o de antes do editor.
    var espacoLinhas: Double
    /// Espaço entre as peças da linha, em pt (0...12); nil = automático.
    var espacoPecas: Double?
    var alinhamentoVertical: AlinhamentoVertical
    /// Largura mínima do item, em pt (20...200); nil = a do conteúdo.
    var larguraMinima: Double?
    var fonte: FonteItem
    /// Escala do item inteiro (0,7...1,3).
    var tamanhoGeral: Double
    var fundo: FundoItem
    /// Cor do fundo; nil = a cor do estado.
    var corFundoHex: String?
    var faixas: [FaixaCor]
    /// Esconde o item da barra neste estado.
    var oculto: Bool

    static let espacoPadrao = -1.5

    init(pecas: [ItemPeca], pecasBaixo: [ItemPeca] = [], corHex: String,
         alinhamentoCima: AlinhamentoLinha = .esquerda, alinhamentoBaixo: AlinhamentoLinha = .esquerda,
         espacoLinhas: Double = ConfigEstado.espacoPadrao,
         espacoPecas: Double? = nil, alinhamentoVertical: AlinhamentoVertical = .centro, larguraMinima: Double? = nil,
         fonte: FonteItem = .padrao, tamanhoGeral: Double = 1, fundo: FundoItem = .nenhum,
         corFundoHex: String? = nil, faixas: [FaixaCor] = [], oculto: Bool = false) {
        self.pecas = pecas
        self.pecasBaixo = pecasBaixo
        self.corHex = corHex
        self.alinhamentoCima = alinhamentoCima
        self.alinhamentoBaixo = alinhamentoBaixo
        self.espacoLinhas = espacoLinhas
        self.espacoPecas = espacoPecas
        self.alinhamentoVertical = alinhamentoVertical
        self.larguraMinima = larguraMinima
        self.fonte = fonte
        self.tamanhoGeral = tamanhoGeral
        self.fundo = fundo
        self.corFundoHex = corFundoHex
        self.faixas = faixas
        self.oculto = oculto
    }

    private enum CodingKeys: String, CodingKey {
        case pecas, pecasBaixo, corHex, alinhamentoCima, alinhamentoBaixo, espacoLinhas
        case espacoPecas, alinhamentoVertical, larguraMinima, fonte, tamanhoGeral, fundo, corFundoHex, faixas, oculto
    }

    /// Aceita as configs antigas: sem `pecasBaixo` e com as peças como lista de nomes (`[String]`).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pecas = try Self.lerItens(c, .pecas) ?? []
        pecasBaixo = try Self.lerItens(c, .pecasBaixo) ?? []
        corHex = try c.decode(String.self, forKey: .corHex)
        alinhamentoCima = try c.decodeIfPresent(AlinhamentoLinha.self, forKey: .alinhamentoCima) ?? .esquerda
        alinhamentoBaixo = try c.decodeIfPresent(AlinhamentoLinha.self, forKey: .alinhamentoBaixo) ?? .esquerda
        espacoLinhas = try c.decodeIfPresent(Double.self, forKey: .espacoLinhas) ?? Self.espacoPadrao
        espacoPecas = try c.decodeIfPresent(Double.self, forKey: .espacoPecas)
        alinhamentoVertical = try c.decodeIfPresent(AlinhamentoVertical.self, forKey: .alinhamentoVertical) ?? .centro
        larguraMinima = try c.decodeIfPresent(Double.self, forKey: .larguraMinima)
        fonte = try c.decodeIfPresent(FonteItem.self, forKey: .fonte) ?? .padrao
        tamanhoGeral = try c.decodeIfPresent(Double.self, forKey: .tamanhoGeral) ?? 1
        fundo = try c.decodeIfPresent(FundoItem.self, forKey: .fundo) ?? .nenhum
        corFundoHex = try c.decodeIfPresent(String.self, forKey: .corFundoHex)
        faixas = try c.decodeIfPresent([FaixaCor].self, forKey: .faixas) ?? []
        oculto = try c.decodeIfPresent(Bool.self, forKey: .oculto) ?? false
    }

    private static func lerItens(_ c: KeyedDecodingContainer<CodingKeys>, _ chave: CodingKeys) throws -> [ItemPeca]? {
        guard c.contains(chave) else { return nil }
        if let itens = try? c.decode([ItemPeca].self, forKey: chave) { return itens }
        return try c.decode([Peca].self, forKey: chave).map { ItemPeca($0) }
    }

    var duasLinhas: Bool { !pecasBaixo.isEmpty }

    func pecas(em linha: LinhaPeca) -> [ItemPeca] { linha == .cima ? pecas : pecasBaixo }

    func alinhamento(em linha: LinhaPeca) -> AlinhamentoLinha { linha == .cima ? alinhamentoCima : alinhamentoBaixo }

    mutating func definirAlinhamento(_ valor: AlinhamentoLinha, em linha: LinhaPeca) {
        if linha == .cima { alinhamentoCima = valor } else { alinhamentoBaixo = valor }
    }

    mutating func alterar(_ linha: LinhaPeca, _ mudar: (inout [ItemPeca]) -> Void) {
        if linha == .cima { mudar(&pecas) } else { mudar(&pecasBaixo) }
    }

    /// Cor do item no estado: a da primeira faixa que vale; senão a cor do estado.
    func corDoEstadoHex(_ s: Situacao) -> String {
        faixas.first(where: { $0.vale(para: s) })?.corHex ?? corHex
    }

    /// Cópia com ids novos em todas as peças e faixas.
    func comNovosIds() -> ConfigEstado {
        var c = self
        c.pecas = pecas.map { $0.comNovoId() }
        c.pecasBaixo = pecasBaixo.map { $0.comNovoId() }
        c.faixas = faixas.map { f in var n = f; n.id = UUID(); return n }
        return c
    }

    static func hexValido(_ h: String) -> Bool {
        h.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil
    }

    /// Limita tudo às faixas aceitas; usado ao importar e ao aplicar formatos salvos.
    func saneado() -> ConfigEstado {
        func limitar(_ v: Double, _ a: Double, _ b: Double) -> Double { v.isFinite ? min(max(v, a), b) : a }
        func hexOuNil(_ h: String?) -> String? { h.flatMap { Self.hexValido($0) ? $0 : nil } }
        func cortar(_ t: String?) -> String? { t.map { String($0.prefix(ItemPeca.limiteTexto)) } }
        func item(_ i: ItemPeca) -> ItemPeca {
            var n = i
            n.tamanho = i.tamanho.map { limitar($0, 7, 16) }
            n.deslocamentoY = i.deslocamentoY.map { limitar($0, -3, 3) }
            n.corHex = hexOuNil(i.corHex)
            n.casas = i.casas.map { min(max($0, 0), 2) }
            n.texto = cortar(i.texto)
            n.prefixo = cortar(i.prefixo)
            n.sufixo = cortar(i.sufixo)
            n.simbolo = i.simbolo.flatMap { ItemPeca.simbolosIcone.contains($0) ? $0 : nil }
            return n
        }
        var c = self
        c.pecas = pecas.prefix(12).map(item)
        c.pecasBaixo = pecasBaixo.prefix(12).map(item)
        c.corHex = Self.hexValido(corHex) ? corHex : "#FFFFFF"
        c.espacoLinhas = limitar(espacoLinhas, -2, 4)
        c.espacoPecas = espacoPecas.map { limitar($0, 0, 12) }
        c.larguraMinima = larguraMinima.map { limitar($0, 20, 200) }
        c.tamanhoGeral = limitar(tamanhoGeral, 0.7, 1.3)
        c.corFundoHex = hexOuNil(corFundoHex)
        c.faixas = faixas.filter { Self.hexValido($0.corHex) && $0.limite.isFinite }.prefix(4).map { f in
            var n = f
            n.limite = f.medida == .ritmo ? limitar(f.limite, 1, 60) : limitar(f.limite, 1, 100)
            return n
        }
        return c
    }

    /// Copia a montagem de outra config (com ids novos), mantendo a cor e as faixas desta.
    func copiandoMontagem(de outra: ConfigEstado) -> ConfigEstado {
        var c = outra.comNovosIds()
        c.corHex = corHex
        c.faixas = faixas
        return c
    }
}

/// Um formato do usuário: a montagem de cada estado, com nome.
struct FormatoSalvo: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var nome: String
    var criadoEm: Date
    /// Chave = rawValue do EstadoBarra.
    var configs: [String: ConfigEstado]

    init(nome: String, configs: [String: ConfigEstado]) {
        self.id = UUID()
        self.nome = nome
        self.criadoEm = Date()
        self.configs = configs
    }

    private enum CodingKeys: String, CodingKey { case id, nome, criadoEm, configs }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        nome = try c.decode(String.self, forKey: .nome)
        criadoEm = try c.decodeIfPresent(Date.self, forKey: .criadoEm) ?? Date()
        configs = try c.decode([String: ConfigEstado].self, forKey: .configs)
    }

    func config(_ e: EstadoBarra) -> ConfigEstado? { configs[e.rawValue] }
}

/// Arquivo de exportação e importação dos formatos.
struct PacoteFormatos: Codable, Sendable {
    static let nomeDoApp = "ConsumoBateria"
    var app = PacoteFormatos.nomeDoApp
    var versao = 1
    var formatos: [FormatoSalvo]

    init(formatos: [FormatoSalvo]) { self.formatos = formatos }

    private enum CodingKeys: String, CodingKey { case app, versao, formatos }

    /// `app` e `versao` são opcionais; se `app` vier e não for o nosso, o arquivo é de outro programa.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let outro = try c.decodeIfPresent(String.self, forKey: .app), outro != Self.nomeDoApp {
            throw DecodingError.dataCorruptedError(forKey: .app, in: c, debugDescription: "Arquivo de outro app")
        }
        app = Self.nomeDoApp
        versao = try c.decodeIfPresent(Int.self, forKey: .versao) ?? 1
        formatos = try c.decode([FormatoSalvo].self, forKey: .formatos)
    }
}

// MARK: - Preferências em forma de tipo

enum MediaRitmo: String, CaseIterable, Codable, Sendable {
    case agora, cincoMin, quinzeMin, umaHora

    var segundos: TimeInterval {
        switch self {
        case .agora: return 0
        case .cincoMin: return 5 * 60
        case .quinzeMin: return 15 * 60
        case .umaHora: return 60 * 60
        }
    }

    var titulo: String {
        switch self {
        case .agora: return "Agora"
        case .cincoMin: return "5 min"
        case .quinzeMin: return "15 min"
        case .umaHora: return "1 h"
        }
    }
}

enum SentidoRitmo: String, CaseIterable, Codable, Sendable {
    case sinais, setas, soCor

    var titulo: String {
        switch self {
        case .sinais: return "− e +"
        case .setas: return "Setas"
        case .soCor: return "Só cor"
        }
    }
}

// MARK: - Dados lidos

/// O que vem além da leitura básica da bateria (temperatura, ciclos, carregador, modo de energia).
struct DetalhesEnergia: Sendable, Equatable {
    var temperaturaC: Double?
    var ciclos: Int?
    var capacidadeFabricaMah: Int?
    /// Potência máxima do carregador, em W.
    var adaptadorW: Double?
    var adaptadorNome: String?
    /// PowerTelemetryData/SystemPowerIn: tudo o que entra pelo carregador, em W.
    var entradaSistemaW: Double?
    var cargaOtimizada: Bool
    var poucaEnergia: Bool
    /// Condição da bateria já em português ("Normal", "Manutenção recomendada").
    var condicao: String?
    /// MaxCapacity quando vem em % (o que o Ajustes do Sistema mostra como saúde).
    var saudeSistemaPercentual: Int?
    /// DesignCycleCount9C: ciclos de projeto.
    var ciclosProjeto: Int?
    /// Modo de energia atual e o configurado para cada fonte (pmset).
    var modoEnergia: ModoEnergia?
    var modoEnergiaBateria: ModoEnergia?
    var modoEnergiaTomada: ModoEnergia?
    /// `pmset -g cap` lista highpowermode (lido uma vez).
    var altoDesempenhoDisponivel: Bool = false
    /// Energia saindo pelas portas USB, uma entrada por porta com algo ligado.
    var portasUSB: [PortaUSB] = []
    /// Nomes dos aparelhos USB com dados (sem hubs internos nem duplicados).
    var aparelhosUSB: [String] = []

    static let vazio = DetalhesEnergia(
        temperaturaC: nil, ciclos: nil, capacidadeFabricaMah: nil, adaptadorW: nil,
        adaptadorNome: nil, entradaSistemaW: nil, cargaOtimizada: false, poucaEnergia: false)
}

/// Uma porta USB-C com algo ligado, lida de PowerOutDetails (AppleSmartBattery).
struct PortaUSB: Sendable, Equatable, Identifiable {
    var numero: Int
    var watts: Double
    var tensaoV: Double?
    var correnteA: Double?
    /// PDPowermW: o máximo que o Mac reparte entre as portas, em W.
    var maximoCombinadoW: Double?
    /// true com transporte de dados (USB2/USB3/DisplayPort...); false só com energia (CC).
    var comDados: Bool

    var id: Int { numero }
    var nome: String { "USB-C \(numero)" }
}

/// Modo de energia do macOS (pmset powermode: 0, 1, 2).
enum ModoEnergia: Int, Sendable, Equatable, Codable {
    case automatico = 0, poucaEnergia = 1, altoDesempenho = 2

    var titulo: String {
        switch self {
        case .automatico: return "Automático"
        case .poucaEnergia: return "Pouca energia"
        case .altoDesempenho: return "Alto desempenho"
        }
    }
}

/// Gasto estimado de um app (nunca medido: o macOS não dá energia por app sem privilégio).
struct ConsumoApp: Sendable, Identifiable, Equatable {
    /// Bundle id ou nome.
    var id: String
    var nome: String
    /// Estimativa, em W.
    var watts: Double
    /// 0...1, relativa ao app que mais gasta na lista.
    var fracao: Double
}

/// Um ponto do histórico, agregado por minuto.
struct PontoMinuto: Codable, Sendable, Equatable {
    var data: Date
    var percentual: Double
    /// %/h; negativo saindo.
    var ritmo: Double
    /// Negativo saindo da bateria.
    var watts: Double
    var naTomada: Bool
    var carregando: Bool
}

// MARK: - Situação

/// Tudo o que a barra e o painel desenham num instante.
struct Situacao: Sendable {
    var leitura: LeituraBateria
    var estado: EstadoBarra
    var ritmoMedio: Double?
    var ritmoAgora: Double
    var ritmoUltimaHora: Double?
    /// Minutos até vazia (descarregando) ou até cheia (carregando).
    var minutosAteFim: Double?
    var minutosAte80: Double?
    var detalhes: DetalhesEnergia
    var apps: [ConsumoApp]
    /// Últimas 24 h, um ponto por minuto.
    var serie: [PontoMinuto]

    /// Horário previsto para acabar ou encher.
    var horarioFim: Date? {
        minutosAteFim.map { leitura.data.addingTimeInterval($0 * 60) }
    }

    var horarioAte80: Date? {
        minutosAte80.map { leitura.data.addingTimeInterval($0 * 60) }
    }

    /// Saúde: a do sistema (MaxCapacity em %) se existir; senão capacidade atual sobre a de fábrica
    /// (pode passar de 100); nil sem os dois.
    var saudePercentual: Double? {
        if let sistema = detalhes.saudeSistemaPercentual { return Double(sistema) }
        guard let fab = detalhes.capacidadeFabricaMah, fab > 0, leitura.capacidadeMah > 0 else { return nil }
        return Double(leitura.capacidadeMah) / Double(fab) * 100
    }

    /// Carregando: quanto da entrada vai para a bateria (V x I), em W.
    var paraBateriaW: Double? {
        guard leitura.carregando, leitura.tensaoMv > 0, leitura.correnteMa > 0 else { return nil }
        return leitura.watts
    }

    /// Carregando: quanto da entrada fica com o Mac (entrada do sistema menos a bateria), em W.
    var paraMacW: Double? {
        guard let entrada = detalhes.entradaSistemaW, let bateria = paraBateriaW else { return nil }
        return max(0, entrada - bateria)
    }

    /// Cheia se cheia; carregando se carregando; parado se na tomada sem carregar;
    /// alto se o ritmo for menor que −limite; senão descarregando.
    static func estado(de leitura: LeituraBateria, ritmo: Double?, limiteAlto: Double) -> EstadoBarra {
        if leitura.cheia { return .cheia }
        if leitura.carregando { return .carregando }
        if leitura.naTomada { return .parado }
        if let ritmo, ritmo < -limiteAlto { return .alto }
        return .descarregando
    }
}

// MARK: - Exemplos (só para o modo --foto)

extension Situacao {
    private static func leituraExemplo(percentual: Int, capacidade: Int, correnteMa: Int, tensaoMv: Int,
                                       carregando: Bool, naTomada: Bool, cheia: Bool) -> LeituraBateria {
        LeituraBateria(
            data: Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date()) ?? Date(), percentual: percentual, cargaMah: capacidade * percentual / 100,
            capacidadeMah: capacidade, correnteMa: correnteMa, correnteMediaMa: correnteMa,
            tensaoMv: tensaoMv, carregando: carregando, naTomada: naTomada, cheia: cheia,
            minutosSistema: nil)
    }

    /// Série sintética de 24 h, montada de trás para frente a partir do % atual.
    /// `ritmoEm(k)` dá (ritmo, naTomada, carregando) k minutos atrás; ao chegar em 100% o resto é tomada parada.
    private static func serieSintetica(fim: Date, percentualAtual: Double, capacidadeMah: Int, tensaoMv: Int,
                                       ritmoEm: (Int) -> (Double, Bool, Bool)) -> [PontoMinuto] {
        var pontos: [PontoMinuto] = []
        pontos.reserveCapacity(1440)
        var pct = percentualAtual
        var cheiaDaquiPraTras = false
        let wPorRitmo = Double(capacidadeMah) * Double(tensaoMv) / 1e8   // W por 1 %/h
        for k in 0..<1440 {
            var (ritmo, tomada, carregando) = ritmoEm(k)
            if cheiaDaquiPraTras { (ritmo, tomada, carregando) = (0, true, false); pct = 100 }
            let watts = cheiaDaquiPraTras ? 3.2 : ritmo * wPorRitmo
            pontos.append(PontoMinuto(data: fim.addingTimeInterval(-Double(k) * 60), percentual: pct,
                                      ritmo: ritmo, watts: watts, naTomada: tomada, carregando: carregando))
            pct -= ritmo / 60
            if pct >= 100 { pct = 100; cheiaDaquiPraTras = true }
            pct = max(0, pct)
        }
        return pontos.reversed()
    }

    static var exemploDescarregando: Situacao {
        let leitura = leituraExemplo(percentual: 54, capacidade: 6000, correnteMa: -924, tensaoMv: 11600,
                                     carregando: false, naTomada: false, cheia: false)
        let serie = serieSintetica(fim: leitura.data, percentualAtual: 54, capacidadeMah: 6000, tensaoMv: 11600) { k in
            let ritmo = -(10.5 + 3.5 * sin(Double(k) / 17) + 1.5 * sin(Double(k) / 5))
            return (ritmo, false, false)
        }
        let apps = [
            ConsumoApp(id: "claude", nome: "Claude", watts: 3.1, fracao: 3.1 / 3.3),
            ConsumoApp(id: "chrome", nome: "Google Chrome", watts: 2.4, fracao: 2.4 / 3.3),
            ConsumoApp(id: "teams", nome: "Microsoft Teams", watts: 1.9, fracao: 1.9 / 3.3),
            ConsumoApp(id: "sistema", nome: "Tela e sistema", watts: 3.3, fracao: 1),
        ]
        let detalhes = DetalhesEnergia(
            temperaturaC: 27, ciclos: 37, capacidadeFabricaMah: 6000, adaptadorW: nil, adaptadorNome: nil,
            entradaSistemaW: nil, cargaOtimizada: false, poucaEnergia: true,
            condicao: "Normal", saudeSistemaPercentual: 100, ciclosProjeto: 1000,
            modoEnergia: .poucaEnergia, modoEnergiaBateria: .poucaEnergia, modoEnergiaTomada: .automatico,
            altoDesempenhoDisponivel: true,
            portasUSB: [PortaUSB(numero: 3, watts: 6.5, tensaoV: 5.0, correnteA: 1.25, maximoCombinadoW: 15, comDados: false)])
        return Situacao(leitura: leitura, estado: .descarregando, ritmoMedio: -11.3, ritmoAgora: -15.4,
                        ritmoUltimaHora: -10.8, minutosAteFim: 286, minutosAte80: nil,
                        detalhes: detalhes, apps: apps, serie: serie)
    }

    /// Números de PainelCarregando.dc.html. O desenho tem "+4.480 mA" e "Bateria 52 W" que não fecham com
    /// 12,6 V; aqui vale a divisão de potência (52 W para a bateria + 12 W para o Mac = 64 W).
    static var exemploCarregando: Situacao {
        let leitura = leituraExemplo(percentual: 54, capacidade: 10100, correnteMa: 4130, tensaoMv: 12600,
                                     carregando: true, naTomada: true, cheia: false)
        let serie = serieSintetica(fim: leitura.data, percentualAtual: 54, capacidadeMah: 10100, tensaoMv: 12600) { k in
            if k < 40 { return (38 + 3 * sin(Double(k) / 6), true, true) }   // ligou há 40 min
            return (-(10.5 + 3.5 * sin(Double(k) / 17) + 1.5 * sin(Double(k) / 5)), false, false)
        }
        let detalhes = DetalhesEnergia(
            temperaturaC: 31, ciclos: 37, capacidadeFabricaMah: 10100, adaptadorW: 96,
            adaptadorNome: "Carregador USB-C de 96 W", entradaSistemaW: 64, cargaOtimizada: true, poucaEnergia: false,
            condicao: "Normal", saudeSistemaPercentual: 100, ciclosProjeto: 1000,
            modoEnergia: .automatico, modoEnergiaBateria: .poucaEnergia, modoEnergiaTomada: .automatico,
            altoDesempenhoDisponivel: true,
            portasUSB: [PortaUSB(numero: 1, watts: 4.5, tensaoV: 9.0, correnteA: 0.5, maximoCombinadoW: 15, comDados: true),
                        PortaUSB(numero: 3, watts: 6.5, tensaoV: 5.0, correnteA: 1.25, maximoCombinadoW: 15, comDados: false)],
            aparelhosUSB: ["Teclado Magic", "SSD Externo"])
        let apps = [
            ConsumoApp(id: "chrome", nome: "Google Chrome", watts: 4.2, fracao: 1),
            ConsumoApp(id: "claude", nome: "Claude", watts: 2.6, fracao: 2.6 / 4.2),
            ConsumoApp(id: "sistema", nome: "Tela e sistema", watts: 3.8, fracao: 3.8 / 4.2),
        ]
        return Situacao(leitura: leitura, estado: .carregando, ritmoMedio: 38, ritmoAgora: 41,
                        ritmoUltimaHora: nil, minutosAteFim: 72, minutosAte80: 41,
                        detalhes: detalhes, apps: apps, serie: serie)
    }

    /// Números de Main.dc.html para cada estado.
    static func exemplo(_ estado: EstadoBarra) -> Situacao {
        switch estado {
        case .descarregando:
            return exemploDescarregando
        case .carregando:
            return exemploCarregando
        case .parado:
            let leitura = leituraExemplo(percentual: 80, capacidade: 6000, correnteMa: 0, tensaoMv: 12400,
                                         carregando: false, naTomada: true, cheia: false)
            var s = exemploDescarregando
            s.leitura = leitura
            s.estado = .parado
            s.ritmoMedio = 0; s.ritmoAgora = 0; s.ritmoUltimaHora = nil
            s.minutosAteFim = nil; s.minutosAte80 = nil
            s.detalhes.cargaOtimizada = true; s.detalhes.poucaEnergia = false
            s.apps = []
            return s
        case .alto:
            let leitura = leituraExemplo(percentual: 31, capacidade: 6000, correnteMa: -1966, tensaoMv: 11600,
                                         carregando: false, naTomada: false, cheia: false)
            var s = exemploDescarregando
            s.leitura = leitura
            s.estado = .alto
            s.ritmoMedio = -24.6; s.ritmoAgora = -32.8; s.ritmoUltimaHora = -20.1
            s.minutosAteFim = 75
            return s
        case .cheia:
            let leitura = leituraExemplo(percentual: 100, capacidade: 6000, correnteMa: 430, tensaoMv: 11600,
                                         carregando: false, naTomada: true, cheia: true)
            var s = exemploDescarregando
            s.leitura = leitura
            s.estado = .cheia
            s.ritmoMedio = 0; s.ritmoAgora = 0; s.ritmoUltimaHora = nil
            s.minutosAteFim = nil; s.minutosAte80 = nil
            s.detalhes.poucaEnergia = false
            s.apps = []
            return s
        }
    }
}
