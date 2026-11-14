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
