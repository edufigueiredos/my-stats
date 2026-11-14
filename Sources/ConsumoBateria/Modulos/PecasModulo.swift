import SwiftUI

// Peças, formatos, faixas e avisos dos módulos do sistema. Tipos paralelos aos da bateria (Modelo.swift), gravados à parte:
// as configs da bateria não mudam. Grade de formatos: docs/desenho/modulos/Main.dc.html.

// MARK: - Peças

enum PecaModulo: String, CaseIterable, Codable, Sendable, Identifiable {
    case rotulo, valor, grafico, icone, anel, ponto, texto, separador, horario
    case apps, sistema, nucleos, temperatura, potencia, cargaMedia
    case usada, pressao, swap
    case livre, leitura, escrita
    case baixando, enviando, latencia
    case tempGPU, ventoinha, memoriaGPU

    var id: String { rawValue }

    func titulo(em m: Modulo) -> String {
        switch self {
        case .rotulo: return "Rótulo"
        case .valor:
            switch m {
            case .cpu, .gpu: return "Uso %"
            case .memoria: return "Usada %"
            case .disco: return "Ocupado %"
            case .rede: return "Latência"
            case .sensores: return "Temperatura"
            }
        case .grafico: return "Gráfico"
        case .icone: return "Ícone"
        case .anel: return "Anel"
        case .ponto: return "Ponto de status"
        case .texto: return "Texto livre"
        case .separador: return "Separador ·"
        case .horario: return "Horário"
        case .apps: return "Apps %"
        case .sistema: return "Sistema %"
        case .nucleos: return "Núcleos"
        case .temperatura: return "Temperatura"
        case .potencia: return "Potência W"
        case .cargaMedia: return "Carga média"
        case .usada: return "Usada GB"
        case .pressao: return "Pressão"
        case .swap: return "Swap"
        case .livre: return "Livre"
        case .leitura: return "Leitura"
        case .escrita: return "Escrita"
        case .baixando: return "Baixando"
        case .enviando: return "Enviando"
        case .latencia: return "Latência"
        case .tempGPU: return "Temp. GPU"
        case .ventoinha: return "Ventoinha"
        case .memoriaGPU: return "Memória da GPU"
        }
    }

    /// Peças que o editor oferece em cada módulo, na ordem do desenho.
    static func paleta(_ m: Modulo) -> [PecaModulo] {
        switch m {
        case .cpu: return [.rotulo, .valor, .apps, .sistema, .grafico, .nucleos, .temperatura, .potencia, .cargaMedia,
                           .icone, .anel, .texto, .separador, .horario]
        case .gpu: return [.rotulo, .valor, .grafico, .memoriaGPU, .temperatura, .potencia, .icone, .anel, .texto,
                           .separador, .horario]
        case .memoria: return [.rotulo, .valor, .usada, .pressao, .swap, .grafico, .icone, .anel, .texto, .separador, .horario]
        case .disco: return [.rotulo, .valor, .livre, .leitura, .escrita, .grafico, .icone, .anel, .texto, .separador, .horario]
        case .rede: return [.rotulo, .ponto, .latencia, .baixando, .enviando, .grafico, .icone, .texto, .separador, .horario]
        case .sensores: return [.rotulo, .temperatura, .tempGPU, .potencia, .ventoinha, .grafico, .icone, .anel, .texto,
                                .separador, .horario]
        }
    }

    /// Peças que mostram uma medida e por isso podem ganhar cor por faixa.
    var segueFaixa: Bool {
        switch self {
        case .valor, .grafico, .anel, .nucleos, .temperatura, .tempGPU, .latencia, .usada: return true
        default: return false
        }
    }
}

struct ItemPecaModulo: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var peca: PecaModulo
    var tamanho: Double?
    var negrito: Bool?
    var casas: Int?
    var corHex: String?
    var porFaixa: Bool?
    var deslocamentoY: Double?
    var texto: String?
    var prefixo: String?
    var sufixo: String?

    static let limiteTexto = 24

    init(_ peca: PecaModulo, id: UUID = UUID(), tamanho: Double? = nil, negrito: Bool? = nil, casas: Int? = nil,
         corHex: String? = nil, porFaixa: Bool? = nil, deslocamentoY: Double? = nil, texto: String? = nil,
         prefixo: String? = nil, sufixo: String? = nil) {
        self.id = id
        self.peca = peca
        self.tamanho = tamanho
        self.negrito = negrito
        self.casas = casas
        self.corHex = corHex
        self.porFaixa = porFaixa
        self.deslocamentoY = deslocamentoY
        self.texto = texto
        self.prefixo = prefixo
        self.sufixo = sufixo
    }

    private enum CodingKeys: String, CodingKey {
        case id, peca, tamanho, negrito, casas, corHex, porFaixa, deslocamentoY, texto, prefixo, sufixo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        peca = try c.decode(PecaModulo.self, forKey: .peca)
        tamanho = try c.decodeIfPresent(Double.self, forKey: .tamanho)
        negrito = try c.decodeIfPresent(Bool.self, forKey: .negrito)
        casas = try c.decodeIfPresent(Int.self, forKey: .casas)
        corHex = try c.decodeIfPresent(String.self, forKey: .corHex)
        porFaixa = try c.decodeIfPresent(Bool.self, forKey: .porFaixa)
        deslocamentoY = try c.decodeIfPresent(Double.self, forKey: .deslocamentoY)
        texto = try c.decodeIfPresent(String.self, forKey: .texto)
        prefixo = try c.decodeIfPresent(String.self, forKey: .prefixo)
        sufixo = try c.decodeIfPresent(String.self, forKey: .sufixo)
    }

    func comNovoId() -> ItemPecaModulo {
        var n = self
        n.id = UUID()
        return n
    }
}

/// Decodifica um elemento sem derrubar a lista: peça desconhecida vira nil.
private struct Tolerante<T: Decodable>: Decodable {
    let valor: T?
    init(from decoder: Decoder) throws { valor = try? T(from: decoder) }
}

// MARK: - Faixas

struct FaixaModulo: Codable, Sendable, Equatable {
    var medio: Double
    var alto: Double

    static func padrao(_ m: Modulo) -> FaixaModulo {
        switch m {
        case .cpu, .gpu: return FaixaModulo(medio: 60, alto: 90)
        case .memoria: return FaixaModulo(medio: 70, alto: 90)
        case .disco: return FaixaModulo(medio: 80, alto: 95)
        case .rede: return FaixaModulo(medio: 60, alto: 150)
        case .sensores: return FaixaModulo(medio: 70, alto: 90)
        }
    }

    func nivel(_ v: Double) -> NivelFaixa {
        v >= alto ? .alto : (v >= medio ? .medio : .normal)
    }
}

enum NivelFaixa: Sendable {
    case normal, medio, alto

    /// nil = a cor base da barra.
    var corHex: String? {
        switch self {
        case .normal: return nil
        case .medio: return "#F2CC7A"
        case .alto: return "#FF8A5C"
        }
    }

    /// O peso muda junto com a cor, para não depender só dela.
    var peso: Font.Weight {
        switch self {
        case .normal: return .semibold
        case .medio: return .bold
        case .alto: return .heavy
        }
    }

    static let verdeHex = "#5BD27A"
    static let semRedeTextoHex = "#FFB8A0"
}

// MARK: - Config

struct ConfigModulo: Codable, Sendable, Equatable {
    var pecas: [ItemPecaModulo]
    /// Linha de baixo; vazia = uma linha só.
    var pecasBaixo: [ItemPecaModulo]
    var alinhamentoCima: AlinhamentoLinha
    var alinhamentoBaixo: AlinhamentoLinha
    var espacoLinhas: Double
    var corPorFaixa: Bool
    var faixa: FaixaModulo
    var fonte: FonteItem
    var tamanhoGeral: Double

    static let espacoPadrao = -1.5

    init(pecas: [ItemPecaModulo], pecasBaixo: [ItemPecaModulo] = [],
         alinhamentoCima: AlinhamentoLinha = .esquerda, alinhamentoBaixo: AlinhamentoLinha = .esquerda,
         espacoLinhas: Double = ConfigModulo.espacoPadrao, corPorFaixa: Bool = false, faixa: FaixaModulo,
         fonte: FonteItem = .padrao, tamanhoGeral: Double = 1) {
        self.pecas = pecas
        self.pecasBaixo = pecasBaixo
        self.alinhamentoCima = alinhamentoCima
        self.alinhamentoBaixo = alinhamentoBaixo
        self.espacoLinhas = espacoLinhas
        self.corPorFaixa = corPorFaixa
        self.faixa = faixa
        self.fonte = fonte
        self.tamanhoGeral = tamanhoGeral
    }

    private enum CodingKeys: String, CodingKey {
        case pecas, pecasBaixo, alinhamentoCima, alinhamentoBaixo, espacoLinhas, corPorFaixa, faixa, fonte, tamanhoGeral
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pecas = Self.lerItens(c, .pecas)
        pecasBaixo = Self.lerItens(c, .pecasBaixo)
        alinhamentoCima = (try? c.decodeIfPresent(AlinhamentoLinha.self, forKey: .alinhamentoCima)) ?? .esquerda
        alinhamentoBaixo = (try? c.decodeIfPresent(AlinhamentoLinha.self, forKey: .alinhamentoBaixo)) ?? .esquerda
        espacoLinhas = try c.decodeIfPresent(Double.self, forKey: .espacoLinhas) ?? Self.espacoPadrao
        corPorFaixa = try c.decodeIfPresent(Bool.self, forKey: .corPorFaixa) ?? false
        faixa = (try? c.decodeIfPresent(FaixaModulo.self, forKey: .faixa)) ?? FaixaModulo(medio: 60, alto: 90)
        fonte = (try? c.decodeIfPresent(FonteItem.self, forKey: .fonte)) ?? .padrao
        tamanhoGeral = try c.decodeIfPresent(Double.self, forKey: .tamanhoGeral) ?? 1
    }

    /// Pula o item de peça desconhecida em vez de falhar a lista inteira.
    private static func lerItens(_ c: KeyedDecodingContainer<CodingKeys>, _ chave: CodingKeys) -> [ItemPecaModulo] {
        guard let lista = try? c.decodeIfPresent([Tolerante<ItemPecaModulo>].self, forKey: chave) else { return [] }
        return lista.compactMap(\.valor)
    }

    var duasLinhas: Bool { !pecasBaixo.isEmpty }

    func pecas(em linha: LinhaPeca) -> [ItemPecaModulo] { linha == .cima ? pecas : pecasBaixo }

    func alinhamento(em linha: LinhaPeca) -> AlinhamentoLinha { linha == .cima ? alinhamentoCima : alinhamentoBaixo }

    mutating func definirAlinhamento(_ valor: AlinhamentoLinha, em linha: LinhaPeca) {
        if linha == .cima { alinhamentoCima = valor } else { alinhamentoBaixo = valor }
    }

    mutating func alterar(_ linha: LinhaPeca, _ mudar: (inout [ItemPecaModulo]) -> Void) {
        if linha == .cima { mudar(&pecas) } else { mudar(&pecasBaixo) }
    }

    func comNovosIds() -> ConfigModulo {
        var c = self
        c.pecas = pecas.map { $0.comNovoId() }
        c.pecasBaixo = pecasBaixo.map { $0.comNovoId() }
        return c
    }

    /// Limita tudo às faixas aceitas.
    func saneado() -> ConfigModulo {
        func limitar(_ v: Double, _ a: Double, _ b: Double) -> Double { v.isFinite ? min(max(v, a), b) : a }
        func hexOuNil(_ h: String?) -> String? { h.flatMap { ConfigEstado.hexValido($0) ? $0 : nil } }
        func cortar(_ t: String?) -> String? { t.map { String($0.prefix(ItemPecaModulo.limiteTexto)) } }
        func item(_ i: ItemPecaModulo) -> ItemPecaModulo {
            var n = i
            n.tamanho = i.tamanho.map { limitar($0, 7, 16) }
            n.deslocamentoY = i.deslocamentoY.map { limitar($0, -3, 3) }
            n.corHex = hexOuNil(i.corHex)
            n.casas = i.casas.map { min(max($0, 0), 2) }
            n.texto = cortar(i.texto)
            n.prefixo = cortar(i.prefixo)
            n.sufixo = cortar(i.sufixo)
            return n
        }
        var c = self
        c.pecas = pecas.prefix(12).map(item)
        c.pecasBaixo = pecasBaixo.prefix(12).map(item)
        c.espacoLinhas = limitar(espacoLinhas, -2, 4)
        c.tamanhoGeral = limitar(tamanhoGeral, 0.7, 1.3)
        c.faixa.medio = limitar(faixa.medio, 0, 1000)
        c.faixa.alto = limitar(max(faixa.alto, c.faixa.medio), 0, 1000)
        return c
    }
}

// MARK: - Formatos prontos

enum FormatoModulo: String, CaseIterable, Codable, Sendable {
    case rotuloValor, graficoValor, iconeValor, anelValor, compacto, pontoValor, duasLinhas

    var titulo: String {
        switch self {
        case .rotuloValor: return "Rótulo e valor"
        case .graficoValor: return "Gráfico e valor"
        case .iconeValor: return "Ícone e valor"
        case .anelValor: return "Anel e valor"
        case .compacto: return "Compacto"
        case .pontoValor: return "Ponto e latência"
        case .duasLinhas: return "Duas linhas"
        }
    }

    static func disponiveis(_ m: Modulo) -> [FormatoModulo] {
        var l: [FormatoModulo] = [.rotuloValor, .graficoValor, .iconeValor, .anelValor, .compacto]
        if m == .rede { l.append(.pontoValor) }
        if m == .sensores { l.append(.duasLinhas) }
        return l
    }

    static func padrao(_ m: Modulo) -> FormatoModulo {
        switch m {
        case .rede: return .pontoValor
        case .sensores: return .duasLinhas
        default: return .rotuloValor
        }
    }

    func config(para m: Modulo) -> ConfigModulo {
        func i(_ ps: PecaModulo...) -> [ItemPecaModulo] { ps.map { ItemPecaModulo($0) } }
        let faixa = FaixaModulo.padrao(m)
        func c(_ cima: [ItemPecaModulo], _ baixo: [ItemPecaModulo] = []) -> ConfigModulo {
            ConfigModulo(pecas: cima, pecasBaixo: baixo, faixa: faixa)
        }
        let sensoresDuas = c(i(.temperatura, .separador, .tempGPU), i(.potencia))
        switch self {
        case .rotuloValor: return c(i(.rotulo), i(.valor))
        case .graficoValor: return c(i(.grafico, .valor))
        case .iconeValor: return c(i(.icone, .valor))
        case .anelValor: return c(i(.anel, .valor))
        case .pontoValor: return c(i(.ponto, .latencia))
        case .duasLinhas: return sensoresDuas
        case .compacto:
            switch m {
            case .disco: return c(i(.leitura), i(.escrita))
            case .rede: return c(i(.baixando), i(.enviando))
            case .sensores: return sensoresDuas
            default: return c(i(.rotulo, .valor))
            }
        }
    }
}

// MARK: - Ao clicar

enum AoClicarModulo: String, Codable, CaseIterable, Sendable {
    case painel, visaoGeral, abrirApp

    func titulo(_ m: Modulo) -> String {
        switch self {
        case .painel: return "Painel \(m.comArtigo)"
        case .visaoGeral: return "Visão geral"
        case .abrirApp: return m.nomeApp
        }
    }
}

// MARK: - Avisos

enum TipoAvisoModulo: String, Codable, Sendable {
    case usoAcima, temperaturaAcima, pressaoAlta, swapAcima, espacoAbaixo, latenciaAcima, semRede
}

struct AvisoModulo: Codable, Sendable, Equatable, Identifiable {
    var tipo: TipoAvisoModulo
    var ligado: Bool
    /// % (uso, espaço), °C, GB (swap) ou ms; sem uso em pressão e sem rede.
    var limite: Double
    /// Há quanto tempo a condição precisa durar; 0 = na hora.
    var minutos: Double

    var id: String { tipo.rawValue }

    func texto(_ m: Modulo) -> String {
        func n(_ v: Double) -> String { Formato.numero(v, casas: v.rounded() == v ? 0 : 1) }
        let duracao = minutos > 0 ? " por \(n(minutos)) min" : ""
        switch tipo {
        case .usoAcima: return "Avisar quando passar de \(n(limite))%\(duracao)"
        case .temperaturaAcima: return "Avisar quando a \(m == .gpu ? "GPU" : "CPU") passar de \(n(limite)) °C\(duracao)"
        case .pressaoAlta: return "Avisar quando a pressão ficar alta\(duracao)"
        case .swapAcima: return "Avisar quando o swap passar de \(n(limite)) GB"
        case .espacoAbaixo: return "Avisar quando o espaço livre ficar abaixo de \(n(limite))%"
        case .latenciaAcima: return "Avisar quando a latência passar de \(n(limite)) ms\(duracao)"
        case .semRede: return "Avisar quando ficar sem rede\(duracao)"
        }
    }

    static func padrao(_ m: Modulo) -> [AvisoModulo] {
        switch m {
        case .cpu:
            return [AvisoModulo(tipo: .usoAcima, ligado: true, limite: 90, minutos: 2),
                    AvisoModulo(tipo: .temperaturaAcima, ligado: false, limite: 95, minutos: 0)]
        case .gpu:
            return [AvisoModulo(tipo: .usoAcima, ligado: false, limite: 90, minutos: 2),
                    AvisoModulo(tipo: .temperaturaAcima, ligado: false, limite: 95, minutos: 0)]
        case .memoria:
            return [AvisoModulo(tipo: .pressaoAlta, ligado: false, limite: 0, minutos: 2),
                    AvisoModulo(tipo: .swapAcima, ligado: false, limite: 4, minutos: 0)]
        case .disco:
            return [AvisoModulo(tipo: .espacoAbaixo, ligado: false, limite: 10, minutos: 0)]
        case .rede:
            return [AvisoModulo(tipo: .latenciaAcima, ligado: false, limite: 150, minutos: 2),
                    AvisoModulo(tipo: .semRede, ligado: false, limite: 0, minutos: 1)]
        case .sensores:
            return [AvisoModulo(tipo: .temperaturaAcima, ligado: false, limite: 95, minutos: 2)]
        }
    }
}

// MARK: - Modo da barra e intervalo

enum ModoBarraModulos: String, Codable, CaseIterable, Sendable {
    case umPorModulo, umItemSo, grupos

    var titulo: String {
        switch self {
        case .umPorModulo: return "Um por módulo"
        case .umItemSo: return "Um item só"
        case .grupos: return "Grupos"
        }
    }
}

enum IntervaloModulos: Double, Codable, CaseIterable, Sendable {
    case um = 1, dois = 2, cinco = 5

    var titulo: String {
        switch self {
        case .um: return "1 s"
        case .dois: return "2 s"
        case .cinco: return "5 s"
        }
    }
}

// MARK: - Ajuste de um módulo

struct AjusteModulo: Codable, Sendable, Equatable, Identifiable {
    var modulo: Modulo
    var ligado: Bool = false
    var formato: FormatoModulo
    var config: ConfigModulo
    var aoClicar: AoClicarModulo = .painel
    /// Módulos com o mesmo número saem juntos no modo Grupos.
    var grupo: Int?
    var avisos: [AvisoModulo]

    var id: String { modulo.rawValue }

    init(modulo: Modulo, ligado: Bool = false, formato: FormatoModulo, config: ConfigModulo,
         aoClicar: AoClicarModulo = .painel, grupo: Int? = nil, avisos: [AvisoModulo]) {
        self.modulo = modulo
        self.ligado = ligado
        self.formato = formato
        self.config = config
        self.aoClicar = aoClicar
        self.grupo = grupo
        self.avisos = avisos
    }

    private enum CodingKeys: String, CodingKey { case modulo, ligado, formato, config, aoClicar, grupo, avisos }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let m = try c.decode(Modulo.self, forKey: .modulo)
        let base = Self.padrao(m)
        modulo = m
        ligado = try c.decodeIfPresent(Bool.self, forKey: .ligado) ?? false
        formato = (try? c.decodeIfPresent(FormatoModulo.self, forKey: .formato)) ?? base.formato
        let cfg = (try? c.decodeIfPresent(ConfigModulo.self, forKey: .config)) ?? base.config
        config = cfg.saneado()
        aoClicar = (try? c.decodeIfPresent(AoClicarModulo.self, forKey: .aoClicar)) ?? .painel
        grupo = try c.decodeIfPresent(Int.self, forKey: .grupo)
        // Aviso novo entra com o padrão; aviso gravado vale; tipo desconhecido é ignorado.
        let gravados = ((try? c.decodeIfPresent([Tolerante<AvisoModulo>].self, forKey: .avisos)) ?? []).compactMap(\.valor)
        var lista: [AvisoModulo] = []
        for p in base.avisos {
            lista.append(gravados.first(where: { $0.tipo == p.tipo }) ?? p)
        }
        avisos = lista
    }

    static func padrao(_ m: Modulo) -> AjusteModulo {
        let f = FormatoModulo.padrao(m)
        return AjusteModulo(modulo: m, ligado: false, formato: f, config: f.config(para: m), avisos: AvisoModulo.padrao(m))
    }
}

// MARK: - Textos das peças

/// Texto de cada peça a partir das leituras. Funções puras, sem estado.
enum TextoPecaModulo {
    /// A medida principal do módulo (alimenta valor, anel, faixa e gráfico). nil = sem leitura.
    static func medida(_ m: Modulo, _ l: LeiturasModulos) -> Double? {
        switch m {
        case .cpu: return l.cpu?.uso
        case .gpu: return l.gpu?.uso
        case .memoria:
            guard let mem = l.memoria, mem.totalBytes > 0 else { return nil }
            return mem.usadaPercentual
        case .disco:
            guard let d = l.disco else { return nil }
            return (d.volumes.first(where: \.interno) ?? d.volumes.first)?.ocupadoPercentual
        case .rede:
            guard let r = l.rede, r.conectado else { return nil }
            return r.latenciaMs
        case .sensores: return l.sensores?.cpuC
        }
    }

    static func nivel(_ m: Modulo, config: ConfigModulo, leituras l: LeiturasModulos) -> NivelFaixa {
        if m == .rede, let r = l.rede, !r.conectado { return .alto }
        guard let v = medida(m, l) else { return .normal }
        return config.faixa.nivel(v)
    }

    /// Rede sem conexão (com leitura de rede presente).
    static func semRede(_ l: LeiturasModulos) -> Bool { l.rede.map { !$0.conectado } ?? false }

    /// Fração 0...1 da medida no anel: latência/200, temperatura/110, o resto em %.
    static func fracao(_ m: Modulo, _ l: LeiturasModulos) -> Double {
        guard let v = medida(m, l) else { return 0 }
        let d: Double = m == .rede ? 200 : (m == .sensores ? 110 : 100)
        return min(max(v / d, 0), 1)
    }

    private static func percentual(_ v: Double?, _ casas: Int) -> String {
        guard let v, v.isFinite else { return Formato.semDado }
        return Formato.numero(v, casas: casas) + "%"
    }

    private static func graus(_ c: Double?, _ casas: Int) -> String {
        guard let c, c.isFinite else { return Formato.semDado }
        return Formato.numero(c, casas: casas) + "°"
    }

    private static func watts(_ w: Double?, _ casas: Int) -> String {
        guard let w, w.isFinite else { return Formato.semDado }
        return Formato.numero(w, casas: casas) + " W"
    }

    private static func valorBase(_ m: Modulo, _ l: LeiturasModulos, casas: Int?) -> String {
        switch m {
        case .cpu, .gpu, .memoria, .disco: return percentual(medida(m, l), casas ?? 0)
        case .rede: return latencia(l)
        case .sensores: return graus(l.sensores?.cpuC, casas ?? 0)
        }
    }

    private static func latencia(_ l: LeiturasModulos) -> String {
        guard let r = l.rede else { return Formato.semDado }
        if !r.conectado { return "sem rede" }
        guard let ms = r.latenciaMs else { return Formato.semDado }
        return Formato.ms(ms)
    }

    private static func velocidade(_ seta: String, _ bps: Double?) -> String {
        guard let bps else { return Formato.semDado }
        return seta + " " + Formato.velocidade(bps)
    }

    /// Texto da peça; nil nas peças que se desenham (gráfico, ícone, anel, ponto, núcleos).
    static func texto(_ item: ItemPecaModulo, modulo m: Modulo, leituras l: LeiturasModulos) -> String? {
        let casas = item.casas
        let base: String
        switch item.peca {
        case .grafico, .icone, .anel, .ponto, .nucleos: return nil
        case .rotulo: base = item.texto ?? m.rotuloCurto
        case .valor: base = valorBase(m, l, casas: casas)
        case .separador: base = item.texto ?? "·"
        case .horario: base = Formato.horario(l.data)
        case .texto:
            let valor = valorBase(m, l, casas: casas)
            let temp = graus(m == .gpu ? l.sensores?.gpuC : l.sensores?.cpuC, casas ?? 0)
            base = (item.texto ?? "")
                .replacingOccurrences(of: "{valor}", with: valor)
                .replacingOccurrences(of: "{rotulo}", with: m.rotuloCurto)
                .replacingOccurrences(of: "{temp}", with: temp)
                .replacingOccurrences(of: "{hora}", with: Formato.horario(l.data))
        case .apps: base = percentual(l.cpu?.usuario, casas ?? 0)
        case .sistema: base = percentual(l.cpu?.sistema, casas ?? 0)
        case .temperatura: base = graus(m == .gpu ? l.sensores?.gpuC : l.sensores?.cpuC, casas ?? 0)
        case .tempGPU: base = graus(l.sensores?.gpuC, casas ?? 0)
        case .potencia:
            switch m {
            case .cpu: base = watts(l.energia?.cpuW, casas ?? 0)
            case .gpu: base = watts(l.energia?.gpuW, casas ?? 0)
            default: base = watts(l.sensores?.sistemaW, casas ?? 0)
            }
        case .cargaMedia:
            if let v = l.cpu?.cargaMedia.first { base = Formato.numero(v, casas: casas ?? 1) } else { base = Formato.semDado }
        case .usada:
            if let mem = l.memoria, mem.totalBytes > 0 { base = Formato.bytesMemoria(mem.usadaBytes) } else { base = Formato.semDado }
        case .pressao: base = l.memoria?.pressao.titulo ?? Formato.semDado
        case .swap:
            if let mem = l.memoria { base = Formato.bytesMemoria(mem.swapUsadoBytes) } else { base = Formato.semDado }
        case .livre:
            if let d = l.disco, let v = d.volumes.first(where: \.interno) ?? d.volumes.first {
                base = Formato.bytesDisco(v.livreBytes)
            } else { base = Formato.semDado }
        case .leitura: base = velocidade("↓", l.disco?.leituraBps)
        case .escrita: base = velocidade("↑", l.disco?.escritaBps)
        case .baixando: base = velocidade("↓", l.rede?.baixandoBps)
        case .enviando: base = velocidade("↑", l.rede?.enviandoBps)
        case .latencia: base = latencia(l)
        case .ventoinha:
            if let v = l.sensores?.ventoinhas.first { base = Formato.rpm(v.rpm) } else { base = Formato.semDado }
        case .memoriaGPU:
            if let b = l.gpu?.memoriaEmUsoBytes { base = Formato.bytesMemoria(b) } else { base = Formato.semDado }
        }
        return (item.prefixo ?? "") + base + (item.sufixo ?? "")
    }
}
