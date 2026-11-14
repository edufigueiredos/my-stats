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
        if args.contains("--sensores") {
            // Diagnóstico: lê os sensores duas vezes, imprime e sai.
            let leitor = LeitorSensores()
            var r: LeituraSensores?
            var tempos: [Double] = []
            for _ in 0..<2 {
                let inicio = Date()
                r = leitor.ler(entradaSistemaW: nil, carregadorW: nil)
                tempos.append(Date().timeIntervalSince(inicio) * 1000)
            }
            func t(_ v: Double?) -> String { v.map { String(format: "%.1f °C", $0) } ?? "—" }
            print("CPU \(t(r?.cpuC)) · GPU \(t(r?.gpuC)) · SSD \(t(r?.ssdC)) · Bateria \(t(r?.bateriaC))")
            for v in r?.ventoinhas ?? [] {
                print("\(v.nome): \(Formato.rpm(v.rpm)) · \(v.fracao.map { Formato.percentual($0 * 100) } ?? "—") (máx. \(v.maximoRpm.map(Formato.rpm) ?? "—"))")
            }
            let soc = LeitorEnergiaSoC()
            for _ in 0..<3 {
                RunLoop.main.run(until: Date().addingTimeInterval(2))
                let e = soc.ler()
                print(String(format: "GPU ligada %.0f%% · %.0f MHz (máx. %.0f) · %.1f W",
                             e?.gpuAtivo ?? -1, e?.gpuMHz ?? -1, e?.gpuMaxMHz ?? -1, e?.gpuW ?? -1))
            }
            print(String(format: "1ª leitura %.0f ms, 2ª %.0f ms", tempos[0], tempos[1]))
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegado = AppDelegate(ligarTodosOsModulos: args.contains("--ligar-modulos"))
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
    let monitorModulos: MonitorModulos
    let ajustesModulos: AjustesModulos
    let navegacao: NavegacaoPreferencias

    var body: some View {
        // Módulo desligado não é lido; a prévia do editor usa os dados de exemplo onde falta leitura.
        let leituras = monitorModulos.leituras.completando(com: .exemplo)
        let exemplo = monitorModulos.series.series.isEmpty
        let series = exemplo ? SeriesModulos.exemplo(agora: leituras.data) : monitorModulos.series
        PreferenciasComMenu(ajustes: .compartilhado, ajustesModulos: ajustesModulos, navegacao: navegacao,
                            leituras: leituras, series: series, situacao: monitor.situacao,
                            abrirAoIniciar: monitor.abrirAoIniciar,
                            alternarAbrirAoIniciar: { monitor.alternarAbrirAoIniciar($0) })
    }
}

private extension LeiturasModulos {
    /// Mantém o que foi lido e completa o resto com `outro` (prévia das Preferências).
    func completando(com outro: LeiturasModulos) -> LeiturasModulos {
        var l = self
        l.cpu = cpu ?? outro.cpu
        l.gpu = gpu ?? outro.gpu
        l.memoria = memoria ?? outro.memoria
        l.disco = disco ?? outro.disco
        l.rede = rede ?? outro.rede
        l.sensores = sensores ?? outro.sensores
        l.energia = energia ?? outro.energia
        if l.ligadoDesde == nil { l.ligadoDesde = outro.ligadoDesde }
        return l
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: Monitor?
    private var monitorModulos: MonitorModulos?
    private var barra: ControladorBarra?
    private var barraModulos: ControladorModulos?
    private let ajustesModulos: AjustesModulos
    private let navegacaoPreferencias = NavegacaoPreferencias()

    /// `ligarTodosOsModulos` (--ligar-modulos): para conferir a barra sem mexer no UserDefaults do dono.
    init(ligarTodosOsModulos: Bool = false) {
        if ligarTodosOsModulos {
            let a = AjustesModulos(persistir: false)
            for m in Modulo.allCases { a.alternar(m, ligado: true) }
            ajustesModulos = a
        } else {
            ajustesModulos = .compartilhado
        }
        super.init()
    }
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
            abrirPreferencias: { [weak self] in self?.abrirPreferencias(pagina: .bateria) },
            pegarSituacao: { monitor.situacao },
            abrirPreferenciasModulos: { [weak self] in self?.abrirPreferencias(pagina: .modulo(.cpu)) },
            ajustesModulos: ajustesModulos)
        observar()

        // Os módulos nascem depois da bateria, para o item dela ficar na ponta direita.
        let modulos = MonitorModulos(ajustes: ajustesModulos) { (monitor.detalhes.entradaSistemaW, monitor.detalhes.adaptadorW) }
        monitorModulos = modulos
        barraModulos = ControladorModulos(
            monitor: modulos, ajustes: ajustesModulos,
            pegarSituacao: { monitor.situacao },
            abrirPreferencias: { [weak self] pagina in self?.abrirPreferencias(pagina: pagina) },
            abrirBateria: { [weak self] in
                // Dá tempo de o popover dos módulos fechar antes de abrir o da bateria.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    self?.barra?.abrirPopover()
                }
            })
        barra?.definirVisivel(ajustesModulos.bateriaNaBarra)
        observarModulos()
    }

    func applicationWillTerminate(_ notificacao: Notification) {
        monitor?.salvar()
        monitorModulos?.gravarRedeAgora()
    }

    /// Mesma ideia de `observar()`, para os módulos: leitura, séries e ajustes que mudam a barra.
    private func observarModulos() {
        guard let monitorModulos else { return }
        let a = ajustesModulos
        withObservationTracking {
            _ = monitorModulos.leituras
            _ = monitorModulos.series
            _ = a.modulos
            _ = a.modoBarra
            _ = a.intervalo
            _ = a.bateriaNaBarra
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.barraModulos?.reconstruirSeNecessario()
                self.barraModulos?.redesenhar()
                self.monitorModulos?.reavaliar()
                self.barra?.definirVisivel(self.ajustesModulos.bateriaNaBarra)
                self.observarModulos()
            }
        }
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

    private func abrirPreferencias(pagina: PaginaPreferencias = .bateria) {
        guard let monitor, let monitorModulos else { return }
        navegacaoPreferencias.pagina = pagina
        let ajustesModulos = self.ajustesModulos
        let navegacao = navegacaoPreferencias
        mostrar(&janelaPreferencias, titulo: "Preferências", tamanho: NSSize(width: 1040, height: 780),
                minimo: NSSize(width: 860, height: 560)) {
            AnyView(RaizTematica {
                PreferenciasAoVivo(monitor: monitor, monitorModulos: monitorModulos,
                                   ajustesModulos: ajustesModulos, navegacao: navegacao)
            })
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
