import AppKit
import Observation

/// Altura útil da tela onde o último ícone da barra foi clicado. Os painéis limitam a altura por ela: com duas telas,
/// `NSScreen.main` pode ser a outra (a da janela em foco), e um painel medido pela tela mais alta passava do espaço
/// e abria com a parte de cima escondida sob a barra de menus.
@MainActor
@Observable
final class TelaDoClique {
    static let compartilhada = TelaDoClique()

    private(set) var alturaVisivel: CGFloat = NSScreen.main?.visibleFrame.height ?? 700

    /// Chamar antes de abrir o popover preso a `botao`.
    func usar(_ botao: NSView) {
        if let h = (botao.window?.screen ?? NSScreen.main)?.visibleFrame.height, h != alturaVisivel { alturaVisivel = h }
    }
}
