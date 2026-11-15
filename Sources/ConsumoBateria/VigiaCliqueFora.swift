import AppKit

/// Fecha um painel quando se clica fora do app (área de trabalho, outra janela).
/// O popover "transient" só fecha sozinho quando o app perde o foco, e um app de barra de menus quase nunca fica em foco:
/// sem isto, clicar na área de trabalho deixava o painel aberto. O monitor global só recebe cliques de outros apps
/// (não precisa de permissão de Acessibilidade) e existe apenas enquanto o painel está aberto.
@MainActor
final class VigiaCliqueFora {
    private var monitor: Any?

    func ligar(_ fechar: @escaping @MainActor () -> Void) {
        desligar()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { _ in
            MainActor.assumeIsolated { fechar() }   // o AppKit chama o monitor global na thread principal
        }
    }

    func desligar() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }
}
