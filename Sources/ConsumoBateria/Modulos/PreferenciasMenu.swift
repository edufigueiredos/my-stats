import SwiftUI

// Preferências com menu lateral (docs/desenho/modulos/Preferencias.dc.html): Geral, Bateria, um editor por módulo,
// Temas e Avisos. As páginas de Geral, Bateria, Temas e Avisos são a JanelaPreferencias filtrada por seção.

enum PaginaPreferencias: Hashable {
    case geral, bateria, modulo(Modulo), temas, avisos
}

@MainActor
@Observable
final class NavegacaoPreferencias {
    var pagina: PaginaPreferencias = .bateria

    init(pagina: PaginaPreferencias = .bateria) { self.pagina = pagina }
}

struct PreferenciasComMenu: View {
    var ajustes: Ajustes
    var ajustesModulos: AjustesModulos
    var navegacao: NavegacaoPreferencias
    var leituras: LeiturasModulos
    var series: SeriesModulos
    var situacao: Situacao?
    var abrirAoIniciar: Bool
    var alternarAbrirAoIniciar: (Bool) -> Void
    var paraFoto = false
    /// Só para o --foto: peça já selecionada no editor do módulo.
    var pecaSelecionadaInicial: (linha: LinhaPeca, peca: PecaModulo)? = nil

    @Environment(\.estilo) private var estilo

    static let larguraMenu: CGFloat = 200

    var body: some View {
        HStack(spacing: 0) {
            menu
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
            if paraFoto {
                pagina.frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                ScrollView { pagina.frame(maxWidth: .infinity, alignment: .topLeading) }
            }
        }
        .frame(width: paraFoto ? 1180 : nil)
        .frame(minWidth: paraFoto ? nil : 940, idealWidth: paraFoto ? nil : 1180,
               minHeight: paraFoto ? nil : 520, idealHeight: paraFoto ? nil : 760)
    }

    // MARK: Menu

    private var menu: some View {
        VStack(alignment: .leading, spacing: 2) {
            itemMenu("Geral", .geral)
            itemMenu("Bateria", .bateria)
            titulo("MÓDULOS")
            ForEach(Modulo.allCases) { m in itemMenu(m.titulo, .modulo(m)) }
            titulo("APARÊNCIA")
            itemMenu("Temas", .temas)
            itemMenu("Avisos", .avisos)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 18)
        .frame(width: Self.larguraMenu)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(estilo.ladrilho.overlay(Color.black.opacity(0.12)))
    }

    private func titulo(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.9)
            .padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 6)
    }

    private func itemMenu(_ nome: String, _ destino: PaginaPreferencias) -> some View {
        let sel = navegacao.pagina == destino
        return Button { navegacao.pagina = destino } label: {
            Text(nome)
                .font(.system(size: 14, weight: sel ? .semibold : .regular))
                .foregroundStyle(sel ? estilo.destaqueTopo : Color.primary.opacity(0.8))
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(sel ? estilo.destaque.opacity(0.16) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(sel ? .isSelected : [])
    }

    // MARK: Página

    @ViewBuilder
    private var pagina: some View {
        switch navegacao.pagina {
        case .geral: janela(.geral)
        case .bateria: janela(.bateria)
        case .temas: janela(.temas)
        case .avisos: janela(.avisos)
        case .modulo(let m):
            PaginaModuloPrefs(modulo: m, ajustes: ajustes, ajustesModulos: ajustesModulos, leituras: leituras,
                              series: series, situacao: situacao, paraFoto: paraFoto,
                              abrirModulo: { navegacao.pagina = .modulo($0) },
                              pecaSelecionadaInicial: pecaSelecionadaInicial)
                .id(m)
        }
    }

    private func janela(_ secao: SecaoPreferencias) -> some View {
        JanelaPreferencias(ajustes: ajustes, abrirAoIniciar: abrirAoIniciar, alternarAbrirAoIniciar: alternarAbrirAoIniciar,
                           paraFoto: paraFoto, pagina: secao, embutida: true)
    }
}
