import AppKit
import SwiftUI

// MARK: - Cor do item

enum CorDaBarra {
    /// Cor a desenhar, ou nil quando o item deve ser "template" (o sistema adapta à barra clara ou escura).
    /// Colorir desligado só pinta o estado alto (laranja, como no desenho); branco puro também vira template,
    /// senão o texto sumiria numa barra clara.
    static func hex(estado: EstadoBarra, config: ConfigEstado, colorir: Bool) -> String? {
        if estado == .alto { return colorir ? config.corHex : EstadoBarra.alto.corPadraoHex }
        guard colorir else { return nil }
        return config.corHex.uppercased() == "#FFFFFF" ? nil : config.corHex
    }
}

// MARK: - Vista do item

/// O item da barra de menus: as peças do estado lado a lado, 22 pt de altura.
struct VistaItemBarra: View {
    var situacao: Situacao
    var config: ConfigEstado
    var colorir: Bool
    var casas: Int
    var sentido: SentidoRitmo
    /// Desenho para virar imagem "template": tudo em preto, só o alfa importa.
    var modelo = false

    private var cor: Color {
        if modelo { return .black }
        if let hex = CorDaBarra.hex(estado: situacao.estado, config: config, colorir: colorir) { return Color(hex: hex) }
        return .primary
    }

    /// Com texto pequeno sobre a bateria, o valor ao lado fica maior (Empilhado).
    private var empilhado: Bool {
        config.pecas.contains(.tempoSobreBateria) || config.pecas.contains(.ritmoSobreBateria)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(config.pecas.enumerated()), id: \.offset) { _, peca in
                VistaPeca(peca: peca, situacao: situacao, cor: cor, casas: casas, sentido: sentido, grande: empilhado)
            }
        }
        .environment(\.desenhoModelo, modelo)
        .frame(height: 22)
        .fixedSize()
    }
}

// MARK: - Imagem para o NSStatusItem

enum RenderizadorBarra {
    /// Renderiza o item em escala 2, 22 pt de altura. Sem cor, a imagem é template e desenhada em preto.
    @MainActor
    static func imagem(situacao: Situacao, config: ConfigEstado, colorir: Bool, casas: Int,
                       sentido: SentidoRitmo) -> NSImage {
        let modelo = CorDaBarra.hex(estado: situacao.estado, config: config, colorir: colorir) == nil
        let vista = VistaItemBarra(situacao: situacao, config: config, colorir: colorir, casas: casas,
                                   sentido: sentido, modelo: modelo)
        let renderizador = ImageRenderer(content: vista)
        renderizador.scale = 2
        guard let cg = renderizador.cgImage else {
            return NSImage(systemSymbolName: "battery.0", accessibilityDescription: "Bateria") ?? NSImage()
        }
        let imagem = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
        imagem.isTemplate = modelo
        return imagem
    }
}

// MARK: - Controlador do NSStatusItem

@MainActor
final class ControladorBarra: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let pegarSituacao: () -> Situacao?
    private let abrirDetalhes: () -> Void
    private let abrirPreferencias: () -> Void

    init(conteudoPainel: @escaping () -> AnyView,
         abrirDetalhes: @escaping () -> Void,
         abrirPreferencias: @escaping () -> Void,
         pegarSituacao: @escaping () -> Situacao?) {
        self.pegarSituacao = pegarSituacao
        self.abrirDetalhes = abrirDetalhes
        self.abrirPreferencias = abrirPreferencias
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: conteudoPainel())
        if let botao = statusItem.button {
            botao.target = self
            botao.action = #selector(clicou(_:))
            botao.sendAction(on: [.leftMouseUp, .rightMouseUp])
            botao.imagePosition = .imageOnly
        }
        redesenhar()
    }

    /// Lê a situação e os Ajustes e põe a imagem na barra. A T8 chama quando o Monitor muda.
    func redesenhar() {
        guard let botao = statusItem.button else { return }
        guard let situacao = pegarSituacao() else {
            let simbolo = NSImage(systemSymbolName: "battery.0", accessibilityDescription: "Sem bateria")
            simbolo?.isTemplate = true
            botao.image = simbolo
            return
        }
        let ajustes = Ajustes.compartilhado
        botao.image = RenderizadorBarra.imagem(
            situacao: situacao, config: ajustes.config(situacao.estado), colorir: ajustes.colorirBarra,
            casas: ajustes.casasDecimais, sentido: ajustes.sentido)
    }

    // MARK: Cliques

    @objc private func clicou(_ remetente: NSStatusBarButton) {
        let evento = NSApp.currentEvent
        let direito = evento?.type == .rightMouseUp
            || (evento?.type == .leftMouseUp && evento?.modifierFlags.contains(.control) == true)
        if direito {
            popover.performClose(nil)
            mostrarMenu()
        } else {
            alternarPopover()
        }
    }

    private func alternarPopover() {
        guard let botao = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: botao.bounds, of: botao, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func mostrarMenu() {
        let menu = NSMenu()
        let atual = Ajustes.compartilhado.formatoBarra
        for formato in FormatoBarra.allCases {
            let item = NSMenuItem(title: formato.titulo, action: #selector(escolherFormato(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = formato.rawValue
            item.state = formato == atual ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let detalhes = NSMenuItem(title: "Mais informações", action: #selector(chamarDetalhes), keyEquivalent: "")
        detalhes.target = self
        menu.addItem(detalhes)
        let preferencias = NSMenuItem(title: "Preferências…", action: #selector(chamarPreferencias), keyEquivalent: ",")
        preferencias.target = self
        menu.addItem(preferencias)
        menu.addItem(.separator())
        let sair = NSMenuItem(title: "Sair", action: #selector(sair), keyEquivalent: "q")
        sair.target = self
        menu.addItem(sair)

        // O menu só aparece preso ao botão enquanto estiver no statusItem.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func escolherFormato(_ item: NSMenuItem) {
        guard let bruto = item.representedObject as? String, let formato = FormatoBarra(rawValue: bruto) else { return }
        Ajustes.compartilhado.aplicar(formato)
        redesenhar()
    }

    @objc private func chamarDetalhes() { abrirDetalhes() }
    @objc private func chamarPreferencias() { abrirPreferencias() }
    @objc private func sair() { NSApp.terminate(nil) }
}

// MARK: - Conferência (modo --foto)

@MainActor
enum FotoBarra {
    /// O item sobre uma faixa que imita a barra de menus escura de Main.dc.html, com a predefinição do formato.
    static func imagemDeConferencia(formato: FormatoBarra, estado: EstadoBarra) -> NSImage {
        let situacao = Situacao.exemplo(estado)
        let config = ConfigEstado(pecas: formato.pecas(para: estado), corHex: estado.corPadraoHex)
        // Como no desenho, só o consumo alto é colorido; o resto fica branco.
        let vista = VistaItemBarra(situacao: situacao, config: config, colorir: false, casas: 1, sentido: .sinais)
        let faixa = ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(hex: "#5A1E1C"), Color(hex: "#7A2A26")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Text("13/11")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                vista
                    .padding(.horizontal, 6)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(0.16)))
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .frame(maxWidth: .infinity)
            .background(Color(red: 28 / 255, green: 18 / 255, blue: 16 / 255).opacity(0.55))
        }
        .frame(width: 250, height: 56)
        .environment(\.colorScheme, .dark)
        let renderizador = ImageRenderer(content: faixa)
        renderizador.scale = 2
        guard let cg = renderizador.cgImage else { return NSImage() }
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
    }
}
