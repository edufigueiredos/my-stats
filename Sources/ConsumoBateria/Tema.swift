import SwiftUI
import AppKit

// Adaptado do Theme.swift do Budsmith (copiado, sem importar o pacote). Cores conferidas com docs/desenho/Temas.dc.html.

// MARK: - Temas

enum TemaApp: String, CaseIterable, Identifiable {
    case gold, black, white, neon, vidro, classico

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .gold: return "Gold"
        case .black: return "Black"
        case .white: return "White"
        case .neon: return "Neon"
        case .vidro: return "Liquid Glass"
        case .classico: return "Classic"
        }
    }
}

/// Tudo o que uma view precisa para se pintar no tema escolhido.
struct EstiloTema {
    var tema: TemaApp
    var destaque: Color
    var destaqueTopo: Color
    var destaqueBase: Color
    /// Texto e ícones sobre um preenchimento de destaque.
    var sobreDestaque: Color
    /// Fundo opaco, ou nil para manter o do sistema.
    var fundo: Color?
    var cartao: Color
    var ladrilho: Color
    var bordaCartao: Color
    /// Brilho em volta do que está selecionado; nil para visual chapado.
    var brilho: Color?
    var scheme: ColorScheme?
    /// Cor de texto forçada nos temas que fixam claro ou escuro; nil mantém a do sistema.
    var texto: Color?

    var ehNeon: Bool { tema == .neon }
    var ehVidro: Bool { tema == .vidro }
    var degrade: LinearGradient {
        LinearGradient(colors: [destaqueTopo, destaqueBase], startPoint: .top, endPoint: .bottom)
    }
    /// Cor do que fica sobre um fundo selecionado.
    var primeiroPlanoSelecionado: Color { ehNeon ? destaque : sobreDestaque }

    static func make(_ tema: TemaApp, neon: Color) -> EstiloTema {
        switch tema {
        case .gold:
            let topo = Color(hex: "#F2CC7A"), base = Color(hex: "#BD8A33"), ouro = Color(hex: "#E0B357")
            return EstiloTema(tema: tema, destaque: ouro, destaqueTopo: topo, destaqueBase: base,
                              sobreDestaque: Color(hex: "#1F1505"), fundo: Color(hex: "#13100C"),
                              cartao: Color.white.opacity(0.06), ladrilho: Color.white.opacity(0.07), bordaCartao: .clear,
                              brilho: ouro.opacity(0.35), scheme: .dark, texto: Color(hex: "#F5F5F5"))
        case .black:
            return EstiloTema(tema: tema, destaque: Color(hex: "#EBEBEB"), destaqueTopo: Color(hex: "#F7F7F7"),
                              destaqueBase: Color(hex: "#BDBDBD"), sobreDestaque: Color(hex: "#0F0F0F"),
                              fundo: Color(hex: "#0B0B0D"),
                              cartao: Color.white.opacity(0.065), ladrilho: Color.white.opacity(0.07), bordaCartao: .clear,
                              brilho: Color.white.opacity(0.16), scheme: .dark, texto: Color(hex: "#F5F5F5"))
        case .white:
            return EstiloTema(tema: tema, destaque: Color(hex: "#1F1F1F"), destaqueTopo: Color(hex: "#383838"),
                              destaqueBase: Color(hex: "#121212"), sobreDestaque: .white,
                              fundo: Color(hex: "#F6F5F1"),
                              cartao: Color.black.opacity(0.05), ladrilho: Color.black.opacity(0.055), bordaCartao: .clear,
                              brilho: nil, scheme: .light, texto: Color(hex: "#171717"))
        case .neon:
            return EstiloTema(tema: tema, destaque: neon, destaqueTopo: neon, destaqueBase: neon, sobreDestaque: .black,
                              fundo: .black,
                              cartao: neon.opacity(0.05), ladrilho: neon.opacity(0.07), bordaCartao: neon.opacity(0.28),
                              brilho: neon.opacity(0.75), scheme: .dark, texto: Color(hex: "#F5F5F5"))
        case .vidro:
            // Segue o sistema: cor de destaque, claro ou escuro, e o material translúcido atrás.
            return EstiloTema(tema: tema, destaque: .accentColor, destaqueTopo: .accentColor, destaqueBase: .accentColor,
                              sobreDestaque: .white, fundo: nil,
                              cartao: Color.primary.opacity(0.07), ladrilho: Color.primary.opacity(0.08),
                              bordaCartao: Color.primary.opacity(0.10), brilho: nil, scheme: nil, texto: nil)
        case .classico:
            let topo = Color(hex: "#F55A4D"), base = Color(hex: "#CC2440")
            return EstiloTema(tema: tema, destaque: topo, destaqueTopo: topo, destaqueBase: base, sobreDestaque: .white,
                              fundo: Color(hex: "#1E1E1E"),
                              cartao: Color.white.opacity(0.06), ladrilho: Color.white.opacity(0.07), bordaCartao: .clear,
                              brilho: topo.opacity(0.35), scheme: .dark, texto: Color(hex: "#F5F5F5"))
        }
    }
}

private struct EstiloTemaChave: EnvironmentKey {
    static let defaultValue = EstiloTema.make(.gold, neon: Color(hex: "#00F0FF"))
}

extension EnvironmentValues {
    var estilo: EstiloTema {
        get { self[EstiloTemaChave.self] }
        set { self[EstiloTemaChave.self] = newValue }
    }
}

extension Color {
    /// "#RRGGBB"; valor inválido vira o ciano do Neon.
    init(hex: String) {
        let digitos = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digitos.count == 6, let valor = UInt32(digitos, radix: 16) else {
            self = Color(red: 0, green: 0.94, blue: 1)
            return
        }
        self = Color(red: Double((valor >> 16) & 255) / 255, green: Double((valor >> 8) & 255) / 255,
                     blue: Double(valor & 255) / 255)
    }

    var hexString: String {
        let cor = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.cyan
        return String(format: "#%02X%02X%02X", Int(round(cor.redComponent * 255)),
                      Int(round(cor.greenComponent * 255)), Int(round(cor.blueComponent * 255)))
    }
}

/// O vidro de verdade é o fundo da própria janela e não sai fora da tela; o --foto liga isto para um substituto chapado.
enum PreviaVidro {
    nonisolated(unsafe) static var aproximado = false
}

/// Lê o tema salvo e aplica (cores, fundo, claro/escuro) a tudo o que está dentro.
/// `temaFixo` e `neonFixo` ignoram o salvo (modo --foto).
struct RaizTematica<Content: View>: View {
    @AppStorage(Ajustes.chaveTema) private var nomeTema = TemaApp.gold.rawValue
    @AppStorage(Ajustes.chaveCorNeon) private var neonHex = "#00F0FF"
    var temaFixo: TemaApp?
    var neonFixo: Color?
    @ViewBuilder var content: Content

    init(temaFixo: TemaApp? = nil, neonFixo: Color? = nil, @ViewBuilder content: () -> Content) {
        self.temaFixo = temaFixo
        self.neonFixo = neonFixo
        self.content = content()
    }

    var body: some View {
        var estilo = EstiloTema.make(temaFixo ?? TemaApp(rawValue: nomeTema) ?? .gold,
                                     neon: neonFixo ?? Color(hex: neonHex))
        // Na prévia (--foto) o vidro é desenhado sobre um degradê escuro: texto claro e esquema escuro.
        if estilo.ehVidro && PreviaVidro.aproximado {
            estilo.scheme = .dark
            estilo.texto = Color(hex: "#F5F5F5")
        }
        return content
            .modifier(CorDeTexto(cor: estilo.texto))
            .modifier(EsquemaForcado(scheme: estilo.scheme))
            .environment(\.estilo, estilo)
            .tint(estilo.destaque)
            .background {
                if estilo.ehVidro {
                    if PreviaVidro.aproximado {
                        ZStack {
                            LinearGradient(colors: [Color(hex: "#2D6F86"), Color(hex: "#33386F"), Color(hex: "#6A3558")],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        }
                    }
                } else {
                    estilo.fundo ?? Color(nsColor: .windowBackgroundColor)
                }
            }
            .preferredColorScheme(estilo.scheme)
    }
}

/// `preferredColorScheme` sozinho não chega ao texto dentro de um popover da barra de menus.
private struct EsquemaForcado: ViewModifier {
    let scheme: ColorScheme?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let scheme { content.environment(\.colorScheme, scheme) } else { content }
    }
}

private struct CorDeTexto: ViewModifier {
    let cor: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let cor { content.foregroundStyle(cor) } else { content }
    }
}

enum Paleta {
    /// Verde de "cheia" e de estados bons.
    static let bom = Color(hex: "#34C759")
    static let alto = Color(hex: "#FF9F0A")
}

// MARK: - Componentes

struct Cartao<Content: View>: View {
    @Environment(\.estilo) private var estilo
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.cartao))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(estilo.bordaCartao, lineWidth: 1))
    }
}

/// Rótulo de seção: maiúsculas, 11 px, com tracking.
struct RotuloSecao: View {
    @Environment(\.estilo) private var estilo
    let titulo: String
    init(_ titulo: String) { self.titulo = titulo }

    var body: some View {
        Text(titulo)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(estilo.ehNeon ? estilo.destaque.opacity(0.85) : Color.secondary)
            .textCase(.uppercase)
            .tracking(0.9)
    }
}

/// Fundo de um item selecionável: degradê de destaque, contorno brilhante no Neon, vidro tingido no Liquid Glass.
struct FundoSelecionavel: View {
    @Environment(\.estilo) private var estilo
    let selecionado: Bool
    var raio: CGFloat = 11
    var capsula = false

    var body: some View {
        Group {
            if capsula {
                // Retângulo de raio metade da altura, e não `Capsule`, que deixa fios nas pontas no ImageRenderer.
                camadas(RoundedRectangle(cornerRadius: 14, style: .circular))
            } else {
                camadas(RoundedRectangle(cornerRadius: raio, style: .continuous))
            }
        }
        .shadow(color: selecionado ? (estilo.brilho ?? .clear) : .clear,
                radius: estilo.ehNeon ? 9 : 6, y: estilo.ehNeon ? 0 : 2)
    }

    @ViewBuilder
    private func camadas(_ forma: RoundedRectangle) -> some View {
        if estilo.ehVidro {
            camadasVidro(forma)
        } else {
            ZStack {
                if selecionado {
                    if estilo.ehNeon {
                        forma.fill(estilo.destaque.opacity(0.16))
                        forma.strokeBorder(estilo.destaque, lineWidth: 1.5)
                    } else {
                        forma.fill(estilo.degrade)
                    }
                } else {
                    forma.fill(estilo.ladrilho)
                    if estilo.ehNeon { forma.strokeBorder(estilo.destaque.opacity(0.22), lineWidth: 1) }
                }
            }
        }
    }

    @ViewBuilder
    private func camadasVidro(_ forma: RoundedRectangle) -> some View {
        if !selecionado {
            forma.fill(estilo.ladrilho)
        } else if #available(macOS 26.0, *), !PreviaVidro.aproximado {
            forma.fill(Color.clear)
                .glassEffect(.regular.tint(estilo.destaque.opacity(0.85)).interactive(), in: forma)
        } else {
            ZStack {
                forma.fill(estilo.destaque.opacity(0.85))
                forma.strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            }
        }
    }
}

/// Fileira de pílulas de largura igual: um controle segmentado no mesmo estilo dos ladrilhos.
struct LinhaChips<Valor: Hashable>: View {
    @Environment(\.estilo) private var estilo

    struct Opcao {
        var valor: Valor
        var titulo: String
    }

    let opcoes: [Opcao]
    let selecao: Valor?
    let aoEscolher: (Valor) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(opcoes.indices, id: \.self) { i in
                let opcao = opcoes[i]
                let selecionada = opcao.valor == selecao
                Button { aoEscolher(opcao.valor) } label: {
                    Text(opcao.titulo)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundStyle(selecionada ? estilo.primeiroPlanoSelecionado : Color.primary.opacity(0.75))
                        .background(FundoSelecionavel(selecionado: selecionada, capsula: true))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selecionada ? .isSelected : [])
            }
        }
    }
}

/// Linha com título e chave liga/desliga desenhada com shapes (o Toggle nativo some no ImageRenderer).
/// `valor` mostra o limite numa caixinha ao lado, como em Preferencias.dc.html.
struct LinhaAlternar: View {
    @Environment(\.estilo) private var estilo
    let titulo: String
    var valor: String? = nil
    let ligado: Bool
    let aoMudar: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(titulo).font(.system(size: 14))
            Spacer(minLength: 8)
            if let valor {
                Text(valor)
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(estilo.ladrilho))
            }
            Button { aoMudar(!ligado) } label: { chave }
                .buttonStyle(.plain)
                .accessibilityLabel(titulo)
                .accessibilityAddTraits(ligado ? .isSelected : [])
        }
        .frame(minHeight: 48)
    }

    private var chave: some View {
        ZStack(alignment: ligado ? .trailing : .leading) {
            if ligado {
                if estilo.ehNeon {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.destaque.opacity(0.25))
                    RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(estilo.destaque, lineWidth: 1.5)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.degrade)
                }
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.18))
            }
            Circle().fill(Color.white).frame(width: 20, height: 20).padding(2)
        }
        .frame(width: 40, height: 24)
    }
}

/// Botão em pílula na cor de destaque (o estilo proeminente do sistema não usa texto escuro sobre o dourado).
struct EstiloBotaoDestaque: ButtonStyle {
    @Environment(\.estilo) private var estilo

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(estilo.primeiroPlanoSelecionado)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(FundoSelecionavel(selecionado: true, capsula: true))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
