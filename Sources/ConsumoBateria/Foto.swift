import SwiftUI
import AppKit

/// Modo --foto: gera PNGs de conferência numa pasta, com dados de exemplo. Não toca na bateria nem grava
/// nada do app (Ajustes e Historico ficam em memória).
@MainActor
enum Foto {
    private static var gravados: [String] = []

    static func gerar(pasta: String) {
        _ = NSApplication.shared
        let url = URL(fileURLWithPath: pasta, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            print("não consegui criar \(pasta): \(error)")
            return
        }
        gravados = []
        let ajustes = Ajustes(persistir: false)
        let semAcoes = AcoesPainel(maisInformacoes: {}, preferencias: {}, sair: {})

        // Item da barra: cada formato em cada estado, e a grade com todos.
        var imagens: [FormatoBarra: [EstadoBarra: NSImage]] = [:]
        for formato in FormatoBarra.allCases {
            for estado in EstadoBarra.allCases {
                let imagem = FotoBarra.imagemDeConferencia(formato: formato, estado: estado)
                imagens[formato, default: [:]][estado] = imagem
                gravar(imagem, "barra-\(formato.rawValue)-\(estado.rawValue)", em: url)
            }
        }
        png(GradeBarra(imagens: imagens), "barra-todos", em: url)

        // Painéis, Mais informações e Preferências no tema Gold.
        png(RaizTematica(temaFixo: .gold) {
            PainelBateria(situacao: .exemploDescarregando, ajustes: ajustes, acoes: semAcoes)
        }, "painel-descarregando", em: url)
        png(RaizTematica(temaFixo: .gold) {
            PainelBateria(situacao: .exemploCarregando, ajustes: ajustes, acoes: semAcoes)
        }, "painel-carregando", em: url)
        // Altura do popover ao vivo (com limite de tela): o painel não pode encolher e cortar o conteúdo.
        for limite: CGFloat in [1000, 600] {
            let hc = NSHostingController(rootView: RaizTematica(temaFixo: .gold) {
                PainelBateria(situacao: .exemploCarregando, ajustes: ajustes, acoes: semAcoes, alturaMaxima: limite)
            })
            hc.view.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
            for _ in 0..<5 {
                hc.view.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            print("popover com tela de \(Int(limite)) pt: \(Int(hc.view.fittingSize.height)) pt de altura")
        }
        // Painel com a escolha "Carga" no gráfico e a seção Painel das Preferências.
        let ajustesCarga = Ajustes(persistir: false)
        ajustesCarga.modoGrafico = .carga
        png(RaizTematica(temaFixo: .gold) {
            PainelBateria(situacao: .exemploCarregando, ajustes: ajustesCarga, acoes: semAcoes)
        }, "painel-carga", em: url)
        png(RaizTematica(temaFixo: .gold) {
            SecaoPainelPrefs(ajustes: ajustes).padding(24).frame(width: 760, alignment: .leading)
        }, "preferencias-painel", em: url)
        png(RaizTematica(temaFixo: .gold) {
            JanelaDetalhes(historico: .exemplo(agora: Situacao.exemploDescarregando.leitura.data, percentualAgora: 54), situacao: .exemploDescarregando, paraFoto: true)
        }, "detalhes", em: url)
        // Exemplo do dono: em cima só o Tempo, embaixo o Ritmo sobre a bateria, alinhado à esquerda.
        func exemploDono(_ estado: EstadoBarra) -> ConfigEstado {
            ConfigEstado(pecas: [ItemPeca(.tempo)], pecasBaixo: [ItemPeca(.ritmoSobreBateria)],
                         corHex: estado.corPadraoHex, alinhamentoCima: .esquerda, alinhamentoBaixo: .esquerda)
        }
        for estado in EstadoBarra.allCases {
            gravar(FotoBarra.imagemDeConferencia(config: exemploDono(estado), estado: estado),
                   "barra-custom-\(estado.rawValue)", em: url)
        }

        // Preferências com o estado aberto (Descarregando) em duas linhas, alinhado à esquerda (exemplo do dono),
        // e o Consumo alto na predefinição Duas linhas.
        let ajustesDuas = Ajustes(persistir: false)
        ajustesDuas.configs[.descarregando] = exemploDono(.descarregando)
        ajustesDuas.configs[.alto] = FormatoBarra.duasLinhas.config(para: .alto, corHex: EstadoBarra.alto.corPadraoHex)
        png(RaizTematica(temaFixo: .gold) {
            JanelaPreferencias(ajustes: ajustesDuas, abrirAoIniciar: true, alternarAbrirAoIniciar: { _ in }, paraFoto: true,
                              ajustesAbertosInicial: [.descarregando])
        }, "preferencias", em: url)

        // O popover "Ajustar peça" (o NSPopover não sai no ImageRenderer): peça Ritmo sobre a bateria da linha de baixo.
        var itemAjustado = ItemPeca(.ritmoSobreBateria)
        itemAjustado.tamanho = 11
        itemAjustado.negrito = true
        itemAjustado.corHex = "#FF9F0A"
        itemAjustado.deslocamentoY = 1
        let coresPaleta = JanelaPreferencias.coresDaPaleta(.descarregando)
        func painelAjuste(_ item: ItemPeca, duasLinhas: Bool = true) -> some View {
            PainelAjustarPeca(item: item, cores: coresPaleta, tamanhoAuto: 9, negritoAuto: false, duasLinhas: duasLinhas,
                              podeEsquerda: false, podeDireita: true,
                              mudar: { _ in }, moverEsquerda: {}, moverDireita: {}, outraLinha: {}, tirar: {},
                              situacao: .exemploDescarregando, paraFoto: true)
        }
        png(RaizTematica(temaFixo: .gold) { molduraEscura { painelAjuste(itemAjustado) } }, "ajustar-peca", em: url)
        png(RaizTematica(temaFixo: .gold) {
            molduraEscura { painelAjuste(ItemPeca(.texto, tamanho: 10, texto: "{pct} · {tempo}", prefixo: "~", sufixo: " h"), duasLinhas: false) }
        }, "ajustar-peca-texto", em: url)
        png(RaizTematica(temaFixo: .gold) {
            molduraEscura { painelAjuste(ItemPeca(.icone, simbolo: "bolt.fill"), duasLinhas: false) }
        }, "ajustar-peca-icone", em: url)

        // Ajustes do item: largura mínima, alinhamento à direita, pílula, fonte arredondada e uma faixa de cor.
        let cfgAjustes = ConfigEstado(
            pecas: [ItemPeca(.ritmo), ItemPeca(.tempo)], corHex: EstadoBarra.descarregando.corPadraoHex,
            alinhamentoCima: .direita, larguraMinima: 90, fonte: .arredondada, fundo: .pilula,
            faixas: [FaixaCor(medida: .ritmo, comparacao: .acimaDe, limite: 15, corHex: "#FF453A")])
        png(RaizTematica(temaFixo: .gold) {
            molduraEscura { PainelItemEstado(config: cfgAjustes, estado: .descarregando, cores: coresPaleta, paraFoto: true) { _ in } }
        }, "ajustes-do-item", em: url)

        // Meus formatos, com dois formatos salvos de exemplo.
        let ajustesSalvos = Ajustes(persistir: false)
        ajustesSalvos.formatosSalvos = formatosDeExemplo()
        png(RaizTematica(temaFixo: .gold) {
            SecaoMeusFormatos(ajustes: ajustesSalvos, casas: 1, sentido: .sinais, paraFoto: true)
                .padding(24)
                .frame(width: 760, alignment: .leading)
        }, "meus-formatos", em: url)
        png(RaizTematica(temaFixo: .gold) {
            JanelaPreferencias(ajustes: ajustesSalvos, abrirAoIniciar: true, alternarAbrirAoIniciar: { _ in }, paraFoto: true)
        }, "preferencias-novidades", em: url)

        // Exemplos de item montado.
        var linhasGrade: [(String, NSImage)] = []
        for (nome, estado, config) in exemplosNovidades() {
            let imagem = FotoBarra.imagemDeConferencia(config: config, estado: estado)
            gravar(imagem, "barra-exemplo-\(nome)", em: url)
            linhasGrade.append((nome, imagem))
        }
        png(GradeNovidades(linhas: linhasGrade), "barra-novidades", em: url)

        // A mesma peça colorida sobre a barra escura e a clara: o resto segue a barra, só a peça fica colorida.
        let cfgCor = ConfigEstado(pecas: [ItemPeca(.ritmo, corHex: "#34C759"), ItemPeca(.porcentagem)],
                                  corHex: "#FFFFFF")
        gravar(FotoBarra.imagemDeConferencia(config: cfgCor, estado: .descarregando, clara: false, colorir: false),
               "barra-cor-escura", em: url)
        gravar(FotoBarra.imagemDeConferencia(config: cfgCor, estado: .descarregando, clara: true, colorir: false),
               "barra-cor-clara", em: url)

        checarConfigsAntigas()
        print(AjustesModulos.checarCompatibilidade() ? "configs de módulos: ok" : "configs de módulos: ERRO")
        fotosModulos(em: url)

        // Um PNG por tema (o vidro de verdade não sai fora da janela: usa o substituto chapado).
        PreviaVidro.aproximado = true
        for tema in TemaApp.allCases {
            png(RaizTematica(temaFixo: tema, neonFixo: Color(hex: "#00F0FF")) {
                PainelBateria(situacao: .exemploDescarregando, ajustes: ajustes, acoes: semAcoes)
            }, "tema-\(tema.rawValue)", em: url)
        }
        PreviaVidro.aproximado = false

        print("Gravados \(gravados.count) arquivos em \(pasta):")
        gravados.forEach { print("  \($0)") }
    }

    /// Moldura escura dos painéis soltos (o popover de verdade tem o fundo do sistema).
    private static func molduraEscura<V: View>(@ViewBuilder _ conteudo: () -> V) -> some View {
        conteudo()
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: "#2A2118")))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
            .padding(16)
            .background(Color(hex: "#13100C"))
            .environment(\.colorScheme, .dark)
    }

    private static func formatosDeExemplo() -> [FormatoSalvo] {
        func configs(_ f: (EstadoBarra) -> ConfigEstado) -> [String: ConfigEstado] {
            Dictionary(uniqueKeysWithValues: EstadoBarra.allCases.map { ($0.rawValue, f($0)) })
        }
        let noturno = FormatoSalvo(nome: "Discreto", configs: configs { e in
            ConfigEstado(pecas: [ItemPeca(.ritmo), ItemPeca(.tempo, formatoTempo: .horasMinutos)],
                         corHex: e.corPadraoHex, fonte: .monoespacada, tamanhoGeral: 0.9)
        })
        let completo = FormatoSalvo(nome: "Duas linhas com pílula", configs: configs { e in
            ConfigEstado(pecas: [ItemPeca(.ritmo)], pecasBaixo: [ItemPeca(.porcentagem), ItemPeca(.tempo)],
                         corHex: e.corPadraoHex, larguraMinima: 80, fundo: .pilula)
        })
        return [noturno, completo]
    }

    /// Os exemplos de item montado: nome do arquivo, estado e config.
    private static func exemplosNovidades() -> [(String, EstadoBarra, ConfigEstado)] {
        func c(_ pecas: [ItemPeca], estado: EstadoBarra = .descarregando, baixo: [ItemPeca] = [],
               _ mod: (inout ConfigEstado) -> Void = { _ in }) -> ConfigEstado {
            var cfg = ConfigEstado(pecas: pecas, pecasBaixo: baixo, corHex: estado.corPadraoHex)
            mod(&cfg)
            return cfg
        }
        let base = [ItemPeca(.ritmo), ItemPeca(.tempo)]
        return [
            ("texto-livre", .descarregando, c([ItemPeca(.texto, texto: "{pct} · {tempo}")])),
            ("tempo-4h46", .descarregando, c([ItemPeca(.ritmo), ItemPeca(.tempo, formatoTempo: .horasMinutos)])),
            ("horario-fim", .descarregando, c([ItemPeca(.porcentagem), ItemPeca(.tempo, prefixo: "até ", formatoTempo: .horarioFim)])),
            ("prefixo-sufixo", .descarregando, c([ItemPeca(.ritmo), ItemPeca(.tempo, prefixo: "~", sufixo: " h")])),
            ("largura-minima-direita", .descarregando, c([ItemPeca(.ritmo)]) { $0.larguraMinima = 90; $0.alinhamentoCima = .direita }),
            ("pilula", .descarregando, c(base) { $0.fundo = .pilula }),
            ("contorno", .descarregando, c(base) { $0.fundo = .contorno }),
            ("fonte-arredondada", .descarregando, c(base) { $0.fonte = .arredondada }),
            ("fonte-mono", .descarregando, c(base) { $0.fonte = .monoespacada }),
            ("tamanho-geral-80", .descarregando, c(base) { $0.tamanhoGeral = 0.8 }),
            ("espaco-pecas-8", .descarregando, c([ItemPeca(.bateria), ItemPeca(.ritmo), ItemPeca(.tempo)]) { $0.espacoPecas = 8 }),
            ("alinhamento-vertical-topo", .descarregando, c([ItemPeca(.bateria), ItemPeca(.ritmo)]) { $0.alinhamentoVertical = .topo }),
            ("icone-simbolo", .descarregando, c([ItemPeca(.icone, simbolo: "bolt.fill"), ItemPeca(.ritmo)])),
            ("etiqueta-propria", .descarregando, c([ItemPeca(.etiquetaValor, texto: "CPU")])),
            // O consumo alto de exemplo é 24,6 %/h: o limite de 30 não valeria, então a faixa usa 20.
            ("faixa-cor", .alto, c(base, estado: .alto) {
                $0.faixas = [FaixaCor(medida: .ritmo, comparacao: .acimaDe, limite: 20, corHex: "#FF453A")]
            }),
            ("oculto", .descarregando, c(base) { $0.oculto = true }),
        ]
    }

    /// Lê três JSONs embutidos (antigo, intermediário e atual) e imprime se as configs antigas continuam valendo.
    private static func checarConfigsAntigas() {
        let antigo = ##"{"descarregando":{"pecas":["ritmo","bateria"],"corHex":"#FFFFFF"}}"##
        let intermediario = """
        {"descarregando":{"pecas":[{"id":"8F1C3A52-0B7E-4C1D-9E55-1A2B3C4D5E6F","peca":"ritmo","tamanho":11,"negrito":true,"corHex":"#FF9F0A","deslocamentoY":1}],
        "pecasBaixo":[{"peca":"ritmoSobreBateria"}],"corHex":"#FFFFFF","alinhamentoCima":"direita","alinhamentoBaixo":"centro","espacoLinhas":-1}}
        """
        let atual = """
        {"alto":{"pecas":[{"peca":"texto","texto":"{pct} · {tempo}","prefixo":"~","sufixo":" h","casas":0,"unidade":false,"formatoTempo":"horasMinutos"},{"peca":"icone","simbolo":"bolt.fill"}],
        "pecasBaixo":[],"corHex":"#FF9F0A","alinhamentoCima":"esquerda","alinhamentoBaixo":"esquerda","espacoLinhas":-1.5,
        "espacoPecas":6,"alinhamentoVertical":"topo","larguraMinima":90,"fonte":"arredondada","tamanhoGeral":0.9,"fundo":"pilula","corFundoHex":"#333333",
        "faixas":[{"medida":"ritmo","comparacao":"acimaDe","limite":15,"corHex":"#FF453A"}],"oculto":false}}
        """
        do {
            let decodificador = JSONDecoder()
            for json in [antigo, intermediario, atual] {
                _ = try decodificador.decode([String: ConfigEstado].self, from: Data(json.utf8))
            }
            print("configs antigas: ok")
        } catch {
            print("configs antigas: ERRO \(error)")
        }
    }

    private static func png<V: View>(_ vista: V, _ nome: String, em pasta: URL) {
        let renderizador = ImageRenderer(content: vista)
        renderizador.scale = 2
        guard let imagem = renderizador.nsImage else {
            print("falhou: \(nome)")
            return
        }
        gravar(imagem, nome, em: pasta)
    }

    private static func gravar(_ imagem: NSImage, _ nome: String, em pasta: URL) {
        guard let tiff = imagem.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let dados = rep.representation(using: .png, properties: [:]) else {
            print("falhou: \(nome)")
            return
        }
        let arquivo = pasta.appendingPathComponent("\(nome).png")
        do {
            try dados.write(to: arquivo)
            gravados.append("\(nome).png")
        } catch {
            print("falhou: \(nome): \(error)")
        }
    }
}

/// Grade de Main.dc.html: uma linha por formato, uma coluna por estado.
private struct GradeBarra: View {
    let imagens: [FormatoBarra: [EstadoBarra: NSImage]]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("").frame(width: 110, alignment: .leading)
                ForEach(EstadoBarra.allCases) { estado in
                    Text(estado.titulo).frame(width: 250, alignment: .leading)
                }
            }
            ForEach(FormatoBarra.allCases) { formato in
                HStack(spacing: 10) {
                    Text(formato.titulo).frame(width: 110, alignment: .leading)
                    ForEach(EstadoBarra.allCases) { estado in
                        if let imagem = imagens[formato]?[estado] {
                            Image(nsImage: imagem)
                        }
                    }
                }
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.7))
        .padding(20)
        .background(Color(hex: "#13100C"))
        .environment(\.colorScheme, .dark)
    }
}

/// Grade dos exemplos novos: o nome à esquerda e a barra à direita, uma por linha.
private struct GradeNovidades: View {
    let linhas: [(String, NSImage)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(linhas.enumerated()), id: \.offset) { _, linha in
                HStack(spacing: 14) {
                    Text(linha.0).frame(width: 190, alignment: .leading)
                    Image(nsImage: linha.1)
                }
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.7))
        .padding(20)
        .background(Color(hex: "#13100C"))
        .environment(\.colorScheme, .dark)
    }
}


// MARK: - Módulos do sistema

private extension Foto {
    /// Barra, formatos, agrupamento, faixas, painéis e Preferências dos módulos (docs/desenho/modulos/), no tema Gold.
    static func fotosModulos(em url: URL) {
        let leituras = LeiturasModulos.exemplo
        let series = SeriesModulos.exemplo(agora: leituras.data)
        let acoes = AcoesModulo.nenhuma

        png(RaizTematica(temaFixo: .gold) { QuadroBarraModulos(leituras: leituras, series: series) }, "modulos-barra", em: url)
        png(RaizTematica(temaFixo: .gold) { QuadroFormatosModulos(leituras: leituras, series: series) }, "modulos-formatos", em: url)
        png(RaizTematica(temaFixo: .gold) { QuadroAgruparModulos(leituras: leituras) }, "modulos-agrupar", em: url)
        png(RaizTematica(temaFixo: .gold) { QuadroFaixasModulos(leituras: leituras) }, "modulos-faixas", em: url)

        // Painéis: sem ações e sem limite de altura.
        png(RaizTematica(temaFixo: .gold) {
            PainelGeral(leituras: leituras, series: series, situacao: .exemplo(.parado), acoes: acoes)
        }, "painel-geral", em: url)
        png(RaizTematica(temaFixo: .gold) { PainelCPU(leituras: leituras, series: series, acoes: acoes) }, "painel-cpu", em: url)
        png(RaizTematica(temaFixo: .gold) { PainelGPU(leituras: leituras, series: series, acoes: acoes) }, "painel-gpu", em: url)
        png(RaizTematica(temaFixo: .gold) { PainelMemoria(leituras: leituras, series: series, acoes: acoes) }, "painel-memoria", em: url)
        png(RaizTematica(temaFixo: .gold) { PainelDisco(leituras: leituras, series: series, acoes: acoes) }, "painel-disco", em: url)
        png(RaizTematica(temaFixo: .gold) { PainelRede(leituras: leituras, series: series, acoes: acoes) }, "painel-rede", em: url)
        png(RaizTematica(temaFixo: .gold) { PainelCalendario(leituras: leituras, acoes: acoes) }, "painel-calendario", em: url)
        png(RaizTematica(temaFixo: .gold) {
            PainelSensores(leituras: leituras, series: series, acoes: acoes,
                           avisoTitulo: "Avisar acima de 95 °C na CPU", avisoDica: "Por mais de 2 min seguidos. Muda nas Preferências.")
        }, "painel-sensores", em: url)

        // Altura do popover de um painel novo com limite de tela, como o teste do painel da bateria.
        let limite: CGFloat = 600
        let hc = NSHostingController(rootView: RaizTematica(temaFixo: .gold) {
            PainelCPU(leituras: leituras, series: series, acoes: acoes, alturaMaxima: limite)
        })
        hc.view.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
        for _ in 0..<5 {
            hc.view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        print("painel cpu com tela de \(Int(limite)) pt: \(Int(hc.view.fittingSize.height)) pt de altura")

        // Preferências com o menu lateral: todos os módulos ligados, a peça "Uso %" da linha de baixo selecionada.
        let ajustesBateria = Ajustes(persistir: false)
        ajustesBateria.aplicar(.duasLinhas)
        let todos = AjustesModulos(persistir: false)
        for m in Modulo.allCases { todos.alternar(m, ligado: true) }
        todos.atualizarConfig(.cpu) { c in
            c.pecas = [ItemPecaModulo(.rotulo)]
            c.pecasBaixo = [ItemPecaModulo(.valor, tamanho: 13, negrito: true, porFaixa: true), ItemPecaModulo(.grafico)]
        }
        png(RaizTematica(temaFixo: .gold) {
            PreferenciasComMenu(ajustes: ajustesBateria, ajustesModulos: todos, navegacao: NavegacaoPreferencias(pagina: .modulo(.cpu)),
                                leituras: leituras, series: series, situacao: .exemplo(.parado), abrirAoIniciar: true,
                                alternarAbrirAoIniciar: { _ in }, paraFoto: true,
                                pecaSelecionadaInicial: (.baixo, .valor))
        }, "preferencias-modulos", em: url)
        png(RaizTematica(temaFixo: .gold) {
            PreferenciasComMenu(ajustes: ajustesBateria, ajustesModulos: todos, navegacao: NavegacaoPreferencias(pagina: .modulo(.sensores)),
                                leituras: leituras, series: series, situacao: .exemplo(.parado), abrirAoIniciar: true,
                                alternarAbrirAoIniciar: { _ in }, paraFoto: true,
                                pecaSelecionadaInicial: (.cima, .temperatura))
        }, "preferencias-modulos-sensores", em: url)
        png(RaizTematica(temaFixo: .gold) {
            PreferenciasComMenu(ajustes: ajustesBateria, ajustesModulos: todos, navegacao: NavegacaoPreferencias(pagina: .modulo(.calendario)),
                                leituras: leituras, series: series, situacao: .exemplo(.parado), abrirAoIniciar: true,
                                alternarAbrirAoIniciar: { _ in }, paraFoto: true,
                                pecaSelecionadaInicial: (.cima, .data))
        }, "preferencias-modulos-calendario", em: url)
        // Texto livre com os marcadores do módulo (GPU).
        todos.atualizarConfig(.gpu) { c in
            c.pecas = [ItemPecaModulo(.texto, texto: "GPU {valor} · {temp} · {watts}")]
            c.pecasBaixo = []
        }
        png(RaizTematica(temaFixo: .gold) {
            PreferenciasComMenu(ajustes: ajustesBateria, ajustesModulos: todos, navegacao: NavegacaoPreferencias(pagina: .modulo(.gpu)),
                                leituras: leituras, series: series, situacao: .exemplo(.parado), abrirAoIniciar: true,
                                alternarAbrirAoIniciar: { _ in }, paraFoto: true,
                                pecaSelecionadaInicial: (.cima, .texto))
        }, "preferencias-modulos-texto-livre", em: url)
    }
}

private let corBarraModulos = Color(hex: "#2B1F38")

private func rotuloQuadro(_ s: String) -> some View {
    Text(s)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color(hex: "#F2CC7A"))
        .textCase(.uppercase)
        .tracking(0.9)
}

private func itemModulo(_ m: Modulo, _ config: ConfigModulo, _ l: LeiturasModulos, _ s: SeriesModulos, escala: CGFloat,
                        corBase: Color = .white) -> some View {
    VistaItemModulo(modulo: m, config: config, leituras: l, serie: serieDoItem(m, series: s), corBase: corBase, escala: escala)
}

/// Faixa "Sua barra de hoje" de Main.dc.html: os seis módulos nos formatos padrão e a bateria por último, em escala 2.
private struct QuadroBarraModulos: View {
    let leituras: LeiturasModulos
    let series: SeriesModulos

    private var bateria: some View {
        let estado = EstadoBarra.parado
        return VistaItemBarra(situacao: .exemplo(estado), config: FormatoBarra.duasLinhas.config(para: estado, corHex: "#FFFFFF"),
                              colorir: false, casas: 1, sentido: .sinais, escala: 2, corBase: .white)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            rotuloQuadro("Sua barra de hoje, do nosso jeito")
            HStack(spacing: 30) {
                Spacer(minLength: 0)
                ForEach(AjustesModulos.ordemPadrao) { m in
                    itemModulo(m, FormatoModulo.padrao(m).config(para: m), leituras, series, escala: 2)
                }
                bateria
            }
            .padding(.horizontal, 28)
            .frame(width: 1184, height: 64)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(
                LinearGradient(colors: [Color(hex: "#4A2A63"), Color(hex: "#5B3376"), Color(hex: "#4A2A63")],
                               startPoint: .leading, endPoint: .trailing)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.10)))
            Text("Igual ao seu iStat: rótulo em cima, valor embaixo. A diferença é que cada peça é editável (tamanho, cor, casas, faixa de cor) e o ponto da rede muda de cor com a latência.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.62))
        }
        .padding(24)
        .background(Color(hex: "#0E0C0A"))
        .environment(\.colorScheme, .dark)
    }
}

/// Grade módulos × formatos prontos de Main.dc.html.
private struct QuadroFormatosModulos: View {
    let leituras: LeiturasModulos
    let series: SeriesModulos

    private let formatos: [FormatoModulo] = [.rotuloValor, .graficoValor, .iconeValor, .anelValor, .compacto]
    private let modulos: [Modulo] = [.cpu, .gpu, .memoria, .disco, .rede, .sensores]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                rotuloQuadro("Formatos prontos por módulo")
                Spacer()
                Text("Ponto de partida; depois o editor de peças muda qualquer coisa")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.62))
            }
            HStack(spacing: 8) {
                Color.clear.frame(width: 150, height: 1)
                ForEach(formatos, id: \.self) { f in
                    Text(f.titulo).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                        .frame(width: 198, alignment: .leading)
                }
            }
            ForEach(modulos) { m in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.titulo).font(.system(size: 15, weight: .bold))
                        Text(m.dica).font(.system(size: 12)).foregroundStyle(.white.opacity(0.62))
                    }
                    .frame(width: 150, alignment: .leading)
                    ForEach(formatos, id: \.self) { f in
                        itemModulo(m, f.config(para: m), leituras, series, escala: 1.5)
                            .frame(width: 198, height: 56)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(corBarraModulos))
                    }
                }
            }
            // O Calendário tem formatos próprios (data e hora, próximo compromisso).
            HStack(spacing: 8) {
                Color.clear.frame(width: 150, height: 1)
                ForEach(FormatoModulo.disponiveis(.calendario), id: \.self) { f in
                    Text(f.titulo).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                        .frame(width: 198, alignment: .leading)
                }
            }
            .padding(.top, 6)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Modulo.calendario.titulo).font(.system(size: 15, weight: .bold))
                    Text(Modulo.calendario.dica).font(.system(size: 12)).foregroundStyle(.white.opacity(0.62))
                }
                .frame(width: 150, alignment: .leading)
                ForEach(FormatoModulo.disponiveis(.calendario), id: \.self) { f in
                    itemModulo(.calendario, f.config(para: .calendario), leituras, series, escala: 1.5)
                        .frame(width: 198, height: 56)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(corBarraModulos))
                }
            }
        }
        .padding(24)
        .background(Color(hex: "#0E0C0A"))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

/// Os três cartões "Juntos ou separados": um item por módulo, um item só e grupos.
private struct QuadroAgruparModulos: View {
    let leituras: LeiturasModulos

    private func umaLinha(_ m: Modulo) -> ConfigModulo {
        let faixa = FaixaModulo.padrao(m)
        if m == .rede { return ConfigModulo(pecas: [ItemPecaModulo(.ponto), ItemPecaModulo(.latencia)], faixa: faixa) }
        return ConfigModulo(pecas: [ItemPecaModulo(.rotulo), ItemPecaModulo(.valor)], faixa: faixa)
    }

    private func solto(_ m: Modulo) -> some View {
        itemModulo(m, umaLinha(m), leituras, SeriesModulos(), escala: 1.2)
            .padding(.horizontal, 8)
    }

    private func juntos(_ ms: [Modulo]) -> some View {
        VistaGrupoModulos(itens: ms.map { ($0, umaLinha($0)) }, leituras: leituras, series: SeriesModulos(),
                          corBase: .white, escala: 1.2)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.10)))
    }

    private func cartao<C: View>(_ titulo: String, _ texto: String, padrao: Bool, @ViewBuilder _ itens: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo).font(.system(size: 15, weight: .bold))
                    Text(texto).font(.system(size: 13)).foregroundStyle(.white.opacity(0.62))
                }
                Spacer(minLength: 12)
                if padrao {
                    Text("Padrão").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(hex: "#1F1505"))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LinearGradient(colors: [Color(hex: "#F2CC7A"), Color(hex: "#BD8A33")], startPoint: .top, endPoint: .bottom)))
                }
            }
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                itens()
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(corBarraModulos))
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(width: 600)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay {
            if padrao {
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(hex: "#F2CC7A").opacity(0.55), lineWidth: 1.5)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            rotuloQuadro("Juntos ou separados")
            cartao("Um item por módulo", "Cada um abre o próprio painel. Como o seu iStat hoje.", padrao: true) {
                ForEach([Modulo.cpu, .gpu, .memoria, .rede]) { m in solto(m) }
            }
            cartao("Um item só", "Menos espaço na barra; o clique abre a Visão geral.", padrao: false) {
                VistaItemUnico(modulos: [.cpu, .gpu, .memoria, .rede, .sensores], leituras: leituras, corBase: .white, escala: 1.2)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.10)))
            }
            cartao("Grupos", "Você escolhe quem vai junto, por exemplo CPU com GPU.", padrao: false) {
                juntos([.cpu, .gpu])
                juntos([.memoria, .disco])
                solto(.rede)
            }
        }
        .padding(24)
        .background(Color(hex: "#0E0C0A"))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

/// "Cor por faixa": CPU em 35/83/97, rede em 6 ms/84 ms/sem rede e temperatura em 58/84/99.
private struct QuadroFaixasModulos: View {
    let leituras: LeiturasModulos

    private func comCPU(_ v: Double) -> LeiturasModulos {
        var l = leituras
        l.cpu?.uso = v
        return l
    }

    private func comRede(ms: Double?, conectado: Bool = true) -> LeiturasModulos {
        var l = leituras
        l.rede?.latenciaMs = ms
        l.rede?.conectado = conectado
        return l
    }

    private func comTemperatura(_ c: Double) -> LeiturasModulos {
        var l = leituras
        l.sensores?.cpuC = c
        return l
    }

    private func config(_ m: Modulo, _ pecas: [PecaModulo]) -> ConfigModulo {
        ConfigModulo(pecas: pecas.map { ItemPecaModulo($0) }, corPorFaixa: true, faixa: FaixaModulo.padrao(m))
    }

    private func linha(_ rotulo: String, _ m: Modulo, _ pecas: [PecaModulo], _ casos: [LeiturasModulos]) -> some View {
        HStack(spacing: 12) {
            Text(rotulo).font(.system(size: 13)).foregroundStyle(.white.opacity(0.75)).frame(width: 150, alignment: .leading)
            ForEach(Array(casos.enumerated()), id: \.offset) { _, l in
                itemModulo(m, config(m, pecas), l, SeriesModulos(), escala: 1.4)
                    .frame(width: 150, height: 44)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(corBarraModulos))
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            rotuloQuadro("Cor por faixa (opcional)")
            Text("Barra monocromática por padrão. Ligando as faixas, só o valor muda de cor, e também de peso, para não depender só da cor.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.66)).frame(width: 640, alignment: .leading)
            linha("CPU: até 60 · 60–90 · acima", .cpu, [.valor], [comCPU(35), comCPU(83), comCPU(97)])
            linha("Rede: latência", .rede, [.ponto, .latencia],
                  [comRede(ms: 6), comRede(ms: 84), comRede(ms: nil, conectado: false)])
            linha("Temperatura", .sensores, [.temperatura], [comTemperatura(58), comTemperatura(84), comTemperatura(99)])
        }
        .padding(24)
        .background(Color(hex: "#0E0C0A"))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}
