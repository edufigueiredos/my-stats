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
        png(RaizTematica(temaFixo: .gold) {
            JanelaDetalhes(historico: .exemplo(agora: Situacao.exemploDescarregando.leitura.data, percentualAgora: 54), situacao: .exemploDescarregando, paraFoto: true)
        }, "detalhes", em: url)
        // Preferências com o estado aberto (Descarregando) em duas linhas.
        let ajustesDuas = Ajustes(persistir: false)
        ajustesDuas.configs[.descarregando] = FormatoBarra.duasLinhas.config(
            para: .descarregando, corHex: EstadoBarra.descarregando.corPadraoHex)
        png(RaizTematica(temaFixo: .gold) {
            JanelaPreferencias(ajustes: ajustesDuas, abrirAoIniciar: true, alternarAbrirAoIniciar: { _ in }, paraFoto: true)
        }, "preferencias", em: url)

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
