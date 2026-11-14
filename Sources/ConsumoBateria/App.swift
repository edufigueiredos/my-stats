import SwiftUI
import AppKit
import Observation

@main
enum Entrada {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--foto"), i + 1 < args.count {
            Foto.gerar(pasta: args[i + 1])
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegado = AppDelegate()
        app.delegate = delegado
        app.run()
    }
}

/// Painel que lê o Monitor (@Observable) no próprio corpo, para atualizar ao vivo enquanto está aberto.
private struct PainelAoVivo: View {
    let monitor: Monitor
    let acoes: AcoesPainel

    var body: some View {
        PainelBateria(situacao: monitor.situacao, ajustes: .compartilhado, acoes: acoes,
                      alturaMaxima: NSScreen.main?.visibleFrame.height ?? 700)
    }
}

private struct DetalhesAoVivo: View {
    let monitor: Monitor

    var body: some View {
        JanelaDetalhes(historico: monitor.historico, situacao: monitor.situacao)
    }
}

private struct PreferenciasAoVivo: View {
    let monitor: Monitor

    var body: some View {
        JanelaPreferencias(ajustes: .compartilhado, abrirAoIniciar: monitor.abrirAoIniciar,
                           alternarAbrirAoIniciar: { monitor.alternarAbrirAoIniciar($0) })
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: Monitor?
    private var barra: ControladorBarra?
    private var janelaDetalhes: NSWindow?
    private var janelaPreferencias: NSWindow?

    func applicationDidFinishLaunching(_ notificacao: Notification) {
        let monitor = Monitor()
        self.monitor = monitor
        var acoes = AcoesPainel(
            maisInformacoes: { [weak self] in self?.abrirDetalhes() },
            preferencias: { [weak self] in self?.abrirPreferencias() },
            sair: { NSApp.terminate(nil) })
        acoes.recarregar = { monitor.atualizar() }
        barra = ControladorBarra(
            conteudoPainel: { AnyView(RaizTematica { PainelAoVivo(monitor: monitor, acoes: acoes) }) },
            abrirDetalhes: { [weak self] in self?.abrirDetalhes() },
            abrirPreferencias: { [weak self] in self?.abrirPreferencias() },
            pegarSituacao: { monitor.situacao })
        observar()
    }

    func applicationWillTerminate(_ notificacao: Notification) {
        monitor?.salvar()
    }

    /// Redesenha o item da barra quando a leitura ou um ajuste que o afeta muda; o rastreio vale uma
    /// mudança só, então é registrado de novo a cada vez.
    private func observar() {
        guard let monitor else { return }
        withObservationTracking {
            let a = Ajustes.compartilhado
            _ = monitor.atual
            _ = monitor.detalhes
            _ = a.formatoBarra
            _ = a.configs
            _ = a.colorirBarra
            _ = a.casasDecimais
            _ = a.sentido
            _ = a.mediaRitmo
            _ = a.limiteAlto
            _ = a.estadoEmPrevia
            _ = a.formatosSalvos
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.barra?.redesenhar()
                self?.observar()
            }
        }
    }

    // MARK: Janelas

    private func abrirDetalhes() {
        guard let monitor else { return }
        mostrar(&janelaDetalhes, titulo: "Mais informações", tamanho: NSSize(width: 1240, height: 860),
                minimo: NSSize(width: 1000, height: 700)) {
            AnyView(RaizTematica { DetalhesAoVivo(monitor: monitor) })
        }
    }

    private func abrirPreferencias() {
        guard let monitor else { return }
        mostrar(&janelaPreferencias, titulo: "Preferências", tamanho: NSSize(width: 820, height: 760),
                minimo: NSSize(width: 680, height: 520)) {
            AnyView(RaizTematica { PreferenciasAoVivo(monitor: monitor) })
        }
    }

    private func mostrar(_ janela: inout NSWindow?, titulo: String, tamanho: NSSize, minimo: NSSize,
                         conteudo: () -> AnyView) {
        if janela == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: conteudo()))
            w.title = titulo
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.isReleasedWhenClosed = false
            let visivel = NSScreen.main?.visibleFrame.size ?? tamanho
            w.setContentSize(NSSize(width: min(tamanho.width, visivel.width - 40),
                                    height: min(tamanho.height, visivel.height - 40)))
            w.contentMinSize = NSSize(width: min(minimo.width, visivel.width - 40),
                                      height: min(minimo.height, visivel.height - 40))
            w.center()
            if janela == nil, titulo == "Preferências" {
                // Fechar a janela é só um orderOut: o onDisappear pode não disparar, então zera a prévia aqui.
                NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
                    MainActor.assumeIsolated { Ajustes.compartilhado.estadoEmPrevia = nil }
                }
            }
            janela = w
        }
        NSApp.activate()
        janela?.makeKeyAndOrderFront(nil)
    }
}
