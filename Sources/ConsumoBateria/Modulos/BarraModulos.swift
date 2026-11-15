import SwiftUI
import AppKit
import Observation

/// Qual tela o popover dos módulos mostra: nil = Visão geral.
@MainActor
@Observable
final class NavegacaoPopoverModulos {
    var tela: Modulo? { didSet { aoMudar?() } }
    @ObservationIgnored var aoMudar: (() -> Void)?
    @ObservationIgnored var alturas = MemoriaAlturasPainel()
    @ObservationIgnored var chave: String { tela?.rawValue ?? "geral" }
}

/// Conteúdo do popover: lê o monitor no próprio corpo para atualizar ao vivo.
struct PopoverModulosAoVivo: View {
    let monitor: MonitorModulos
    let navegacao: NavegacaoPopoverModulos
    let ajustes: AjustesModulos
    let pegarSituacao: () -> Situacao?
    let acoes: AcoesModulo

    private var altura: CGFloat { TelaDoClique.compartilhada.alturaVisivel }

    /// Texto do cartão de aviso do painel de Sensores, vindo do aviso de temperatura configurado.
    private var avisoSensores: (titulo: String?, dica: String?) {
        guard let a = ajustes.ajuste(.sensores).avisos.first(where: { $0.tipo == .temperaturaAcima }), a.ligado else {
            return ("Avisos de temperatura desligados", "Ligue nas Preferências.")
        }
        let lim = Formato.numero(a.limite, casas: a.limite.rounded() == a.limite ? 0 : 1)
        let dica = a.minutos > 0
            ? "Por mais de \(Formato.numero(a.minutos, casas: a.minutos.rounded() == a.minutos ? 0 : 1)) min seguidos. Muda nas Preferências."
            : "Muda nas Preferências."
        return ("Avisar acima de \(lim) °C na CPU", dica)
    }

    var body: some View {
        conteudo.environment(\.alturaPainel, ChaveAlturaPainel(memoria: navegacao.alturas, chave: navegacao.chave))
    }

    @ViewBuilder
    private var conteudo: some View {
        let l = monitor.leituras
        let s = monitor.series
        switch navegacao.tela {
        case nil:
            PainelGeral(leituras: l, series: s, situacao: pegarSituacao(), acoes: acoes, alturaMaxima: altura)
        case .cpu?:
            PainelCPU(leituras: l, series: s, acoes: acoes, alturaMaxima: altura)
        case .gpu?:
            PainelGPU(leituras: l, series: s, acoes: acoes, alturaMaxima: altura)
        case .memoria?:
            PainelMemoria(leituras: l, series: s, acoes: acoes, alturaMaxima: altura)
        case .disco?:
            PainelDisco(leituras: l, series: s, acoes: acoes, alturaMaxima: altura)
        case .rede?:
            PainelRede(leituras: l, series: s, acoes: acoes, alturaMaxima: altura)
        case .calendario?:
            PainelCalendario(leituras: l, acoes: acoes, alturaMaxima: altura)
        case .sensores?:
            let aviso = avisoSensores
            PainelSensores(leituras: l, series: s, acoes: acoes, avisoTitulo: aviso.titulo, avisoDica: aviso.dica,
                           alturaMaxima: altura)
        }
    }
}

/// Um NSStatusItem por elemento de `ajustes.itensNaBarra` (um por módulo, um item só ou grupos) e um popover só.
@MainActor
final class ControladorModulos: NSObject, NSPopoverDelegate {
    private struct Item {
        let modulos: [Modulo]
        let statusItem: NSStatusItem
        var observacao: NSKeyValueObservation?
        var ultimaEscura: Bool?
    }

    private let monitor: MonitorModulos
    private let ajustes: AjustesModulos
    private let pegarSituacao: () -> Situacao?
    private let abrirPreferencias: (PaginaPreferencias) -> Void
    private let abrirBateria: () -> Void
    private let popover = NSPopover()
    private let navegacao = NavegacaoPopoverModulos()
    private var itens: [Item] = []
    private var chaveAtual: [[Modulo]] = []
    private weak var botaoAncora: NSStatusBarButton?
    private weak var botaoDoMenu: NSStatusBarButton?

    init(monitor: MonitorModulos, ajustes: AjustesModulos, pegarSituacao: @escaping () -> Situacao?,
         abrirPreferencias: @escaping (PaginaPreferencias) -> Void, abrirBateria: @escaping () -> Void) {
        self.monitor = monitor
        self.ajustes = ajustes
        self.pegarSituacao = pegarSituacao
        self.abrirPreferencias = abrirPreferencias
        self.abrirBateria = abrirBateria
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        navegacao.aoMudar = { [weak self] in self?.atualizarAbertos() }
        let raiz = RaizTematica {
            PopoverModulosAoVivo(monitor: monitor, navegacao: navegacao, ajustes: ajustes,
                                 pegarSituacao: pegarSituacao, acoes: self.acoes)
        }
        popover.contentViewController = NSHostingController(rootView: raiz)
        reconstruirSeNecessario()
        redesenhar()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            await self?.medirPaineisFechados()
        }
    }

    /// Mede, fora da tela, a altura de cada painel ainda não aberto, para o primeiro clique já abrir no tamanho certo.
    private func medirPaineisFechados() async {
        let telas: [Modulo?] = [nil] + Modulo.allCases.map { Optional($0) }
        for tela in telas {
            let nav = NavegacaoPopoverModulos()
            nav.alturas = navegacao.alturas
            nav.tela = tela
            guard nav.alturas.total[nav.chave] == nil else { continue }
            let hc = NSHostingController(rootView: RaizTematica {
                PopoverModulosAoVivo(monitor: monitor, navegacao: nav, ajustes: ajustes,
                                     pegarSituacao: pegarSituacao, acoes: AcoesModulo())
            })
            hc.view.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
            for _ in 0..<4 {
                hc.view.layoutSubtreeIfNeeded()
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }

    // MARK: Itens

    /// Remove e recria os itens quando a composição ou a ordem mudam. Cria da direita para a esquerda: o macOS põe
    /// cada item novo à esquerda dos existentes, e a bateria (criada antes) fica na ponta direita.
    func reconstruirSeNecessario() {
        let novos = ajustes.itensNaBarra
        guard novos != chaveAtual || itens.count != novos.count else { return }
        if popover.isShown { popover.performClose(nil) }
        for i in itens { NSStatusBar.system.removeStatusItem(i.statusItem) }
        itens = []
        chaveAtual = novos
        for modulos in novos.reversed() {
            let si = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            var item = Item(modulos: modulos, statusItem: si)
            if let botao = si.button {
                botao.target = self
                botao.action = #selector(clicou(_:))
                botao.sendAction(on: [.leftMouseUp, .rightMouseUp])
                botao.imagePosition = .imageOnly
                let id = ObjectIdentifier(si)
                item.ultimaEscura = barraEscura(botao)
                item.observacao = botao.observe(\.effectiveAppearance) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.aparenciaMudou(id) }
                }
            }
            itens.append(item)
        }
        itens.reverse()   // da esquerda para a direita, como em itensNaBarra
        redesenhar()
    }

    private func aparenciaMudou(_ id: ObjectIdentifier) {
        guard let i = itens.firstIndex(where: { ObjectIdentifier($0.statusItem) == id }),
              let botao = itens[i].statusItem.button else { return }
        let escura = barraEscura(botao)
        guard escura != itens[i].ultimaEscura else { return }
        itens[i].ultimaEscura = escura
        redesenhar()
    }

    private func barraEscura(_ botao: NSStatusBarButton) -> Bool {
        botao.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    func redesenhar() {
        let l = monitor.leituras
        let s = monitor.series
        for item in itens {
            guard let botao = item.statusItem.button else { continue }
            let base: Color = barraEscura(botao) ? .white : Color.black.opacity(0.85)
            botao.image = imagem(modulos: item.modulos, leituras: l, series: s, corBase: base)
            botao.toolTip = item.modulos.map(\.titulo).joined(separator: " · ")
        }
    }

    private func imagem(modulos: [Modulo], leituras l: LeiturasModulos, series s: SeriesModulos, corBase: Color) -> NSImage {
        if ajustes.modoBarra == .umItemSo {
            let v = VistaItemUnico(modulos: modulos, leituras: l, corBase: corBase, modelo: true)
            return RenderizadorModulos.imagem(v, colorida: false)
        }
        if modulos.count > 1 {
            let pares = modulos.map { ($0, ajustes.ajuste($0).config) }
            let precisa = VistaGrupoModulos(itens: pares, leituras: l, series: s, corBase: corBase).precisaCor
            let v = VistaGrupoModulos(itens: pares, leituras: l, series: s, corBase: corBase, modelo: !precisa)
            return RenderizadorModulos.imagem(v, colorida: precisa)
        }
        guard let m = modulos.first else { return NSImage() }
        let cfg = ajustes.ajuste(m).config
        let serie = serieDoItem(m, series: s)
        let precisa = VistaItemModulo(modulo: m, config: cfg, leituras: l, serie: serie, corBase: corBase).precisaCor
        let v = VistaItemModulo(modulo: m, config: cfg, leituras: l, serie: serie, corBase: corBase, modelo: !precisa)
        return RenderizadorModulos.imagem(v, colorida: precisa)
    }

    // MARK: Cliques

    @objc private func clicou(_ remetente: NSStatusBarButton) {
        guard let item = itens.first(where: { $0.statusItem.button === remetente }) else { return }
        let evento = NSApp.currentEvent
        let direito = evento?.type == .rightMouseUp
            || (evento?.type == .leftMouseUp && evento?.modifierFlags.contains(.control) == true)
        if direito {
            popover.performClose(nil)
            mostrarMenu(item)
            return
        }
        if item.modulos.count == 1, ajustes.modoBarra != .umItemSo, let m = item.modulos.first {
            switch ajustes.ajuste(m).aoClicar {
            case .painel: alternarPopover(tela: m, botao: remetente)
            case .visaoGeral: alternarPopover(tela: nil, botao: remetente)
            case .abrirApp:
                popover.performClose(nil)
                abrirApp(m)
            }
        } else {
            alternarPopover(tela: nil, botao: remetente)
        }
    }

    /// Painel pedido enquanto o anterior ainda fecha: abre no popoverDidClose. Abrir durante a animação de fechar
    /// fazia o macOS posicionar o popover errado (às vezes na outra tela) e o didClose atrasado zerava os painéis abertos.
    private var pendente: (tela: Modulo?, botao: NSStatusBarButton)?
    private var fechando = false

    private func alternarPopover(tela: Modulo?, botao: NSStatusBarButton) {
        let mesmo = botaoAncora === botao
        if popover.isShown && !fechando {
            pendente = mesmo ? nil : (tela, botao)
            popover.performClose(nil)
            return
        }
        if fechando {
            // Clique no mesmo ícone enquanto fecha (o "transient" já fechou pelo clique fora): só fecha.
            pendente = mesmo ? nil : (tela, botao)
            return
        }
        mostrar(tela: tela, botao: botao)
    }

    private func mostrar(tela: Modulo?, botao: NSStatusBarButton) {
        navegacao.tela = tela
        botaoAncora = botao
        TelaDoClique.compartilhada.usar(botao)
        // Abre já com a altura que este painel teve da última vez, em vez da do painel anterior (nunca maior que a tela).
        if let h = navegacao.alturas.total[navegacao.chave] {
            popover.contentSize = NSSize(width: 400, height: min(h, TelaDoClique.compartilhada.alturaVisivel - 40))
        }
        popover.contentViewController?.view.layoutSubtreeIfNeeded()
        popover.show(relativeTo: botao.bounds, of: botao, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        vigia.ligar { [weak self] in self?.popover.performClose(nil) }
        atualizarAbertos()
    }

    /// Diz ao monitor o que está aberto, para ele ler só o necessário.
    private func atualizarAbertos() {
        guard popover.isShown else {
            monitor.paineisAbertos = []
            monitor.geralAberto = false
            return
        }
        if let m = navegacao.tela {
            monitor.geralAberto = false
            monitor.paineisAbertos = [m]
        } else {
            monitor.paineisAbertos = []
            monitor.geralAberto = true
        }
    }

    func popoverWillClose(_ notification: Notification) {
        fechando = true
    }

    private let vigia = VigiaCliqueFora()

    func popoverDidClose(_ notification: Notification) {
        vigia.desligar()
        fechando = false
        monitor.paineisAbertos = []
        monitor.geralAberto = false
        botaoAncora = nil
        if let p = pendente {
            pendente = nil
            // Próxima volta do run loop: a janela do popover anterior termina de sair antes de reabrir.
            DispatchQueue.main.async { [weak self] in self?.mostrar(tela: p.tela, botao: p.botao) }
        }
    }

    // MARK: Ações dos painéis

    private var acoes: AcoesModulo {
        var a = AcoesModulo()
        a.preferencias = { [weak self] in
            guard let self else { return }
            self.popover.performClose(nil)
            self.abrirPreferencias(self.navegacao.tela.map { .modulo($0) } ?? .geral)
        }
        a.visaoGeral = { [weak self] in self?.navegacao.tela = nil }
        a.abrirModulo = { [weak self] m in self?.navegacao.tela = m }
        a.abrirBateria = { [weak self] in
            self?.popover.performClose(nil)
            self?.abrirBateria()
        }
        a.abrirApp = { [weak self] in
            guard let self else { return }
            self.abrirApp(self.navegacao.tela)
        }
        a.ejetar = { url in
            Task { @MainActor in try? NSWorkspace.shared.unmountAndEjectDevice(at: url) }
        }
        a.buscarIPPublico = { await LeitorRede.buscarIPPublico() }
        a.sair = { NSApp.terminate(nil) }
        a.permitirCalendario = { [weak self] in self?.monitor.pedirPermissaoCalendario() }
        a.mesCalendario = { [weak self] d in self?.monitor.mostrarMesCalendario(d) }
        return a
    }

    private func abrirApp(_ m: Modulo?) {
        let espaco = NSWorkspace.shared
        guard let m else { abrirPorId("com.apple.ActivityMonitor"); return }
        switch m {
        case .cpu, .gpu, .memoria, .sensores: abrirPorId("com.apple.ActivityMonitor")
        case .disco: abrirPorId("com.apple.DiskUtility")
        case .rede:
            if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") { espaco.open(url) }
        case .calendario:
            espaco.openApplication(at: URL(fileURLWithPath: "/System/Applications/Calendar.app"),
                                   configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private func abrirPorId(_ id: String) {
        let espaco = NSWorkspace.shared
        guard let url = espaco.urlForApplication(withBundleIdentifier: id) else { return }
        espaco.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Menu do clique direito

    private func mostrarMenu(_ item: Item) {
        let menu = NSMenu()
        if item.modulos.count == 1, let m = item.modulos.first {
            menu.addItem(entrada("Preferências do módulo…", #selector(menuPreferencias(_:)), m.rawValue))
            menu.addItem(entrada(m.nomeApp, #selector(menuAbrirApp(_:)), m.rawValue))
            menu.addItem(entrada("Esconder", #selector(menuEsconder(_:)), m.rawValue))
        } else if let primeiro = item.modulos.first {
            menu.addItem(entrada("Preferências dos módulos…", #selector(menuPreferencias(_:)), primeiro.rawValue))
            let esconder = NSMenuItem(title: "Esconder", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for m in item.modulos { sub.addItem(entrada(m.titulo, #selector(menuEsconder(_:)), m.rawValue)) }
            esconder.submenu = sub
            menu.addItem(esconder)
        }
        menu.addItem(.separator())
        menu.addItem(entrada("Visão geral", #selector(menuVisaoGeral(_:)), nil))
        let sair = NSMenuItem(title: "Sair", action: #selector(menuSair), keyEquivalent: "q")
        sair.target = self
        menu.addItem(sair)

        botaoDoMenu = item.statusItem.button
        // O menu só aparece preso ao botão enquanto estiver no statusItem.
        item.statusItem.menu = menu
        item.statusItem.button?.performClick(nil)
        item.statusItem.menu = nil
    }

    private func entrada(_ titulo: String, _ acao: Selector, _ objeto: String?) -> NSMenuItem {
        let i = NSMenuItem(title: titulo, action: acao, keyEquivalent: "")
        i.target = self
        i.representedObject = objeto
        return i
    }

    private func modulo(de item: NSMenuItem) -> Modulo? {
        (item.representedObject as? String).flatMap(Modulo.init(rawValue:))
    }

    @objc private func menuPreferencias(_ item: NSMenuItem) {
        guard let m = modulo(de: item) else { return }
        abrirPreferencias(.modulo(m))
    }

    @objc private func menuAbrirApp(_ item: NSMenuItem) {
        guard let m = modulo(de: item) else { return }
        abrirApp(m)
    }

    @objc private func menuEsconder(_ item: NSMenuItem) {
        guard let m = modulo(de: item) else { return }
        ajustes.alternar(m, ligado: false)
    }

    @objc private func menuVisaoGeral(_ item: NSMenuItem) {
        guard let botao = botaoDoMenu ?? itens.first?.statusItem.button else { return }
        alternarPopover(tela: nil, botao: botao)
    }

    @objc private func menuSair() { NSApp.terminate(nil) }
}
