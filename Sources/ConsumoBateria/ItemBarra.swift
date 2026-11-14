import AppKit
import SwiftUI

// MARK: - Cor do item

enum CorDaBarra {
    /// Cor a desenhar, ou nil quando o item deve ser "template" (o sistema adapta à barra clara ou escura).
    /// Uma faixa de cor que vale vence tudo, mesmo com Colorir desligado. Sem faixa, Colorir desligado só pinta
    /// o estado alto (laranja, como no desenho). Branco puro vira template, senão o texto sumiria numa barra clara.
    static func hex(estado: EstadoBarra, situacao: Situacao, config: ConfigEstado, colorir: Bool) -> String? {
        if config.faixas.contains(where: { $0.vale(para: situacao) }) {
            let hex = config.corDoEstadoHex(situacao)
            return hex.uppercased() == "#FFFFFF" ? nil : hex
        }
        if estado == .alto { return colorir ? config.corHex : EstadoBarra.alto.corPadraoHex }
        guard colorir else { return nil }
        return config.corHex.uppercased() == "#FFFFFF" ? nil : config.corHex
    }

    static func ehBranco(_ hex: String?) -> Bool { hex == nil || hex?.uppercased() == "#FFFFFF" }
}

// MARK: - Vista do item

/// O item da barra de menus: as peças do estado lado a lado (ou em duas linhas empilhadas), 22 pt de altura.
/// `escala` amplia tudo (prévias do editor).
struct VistaItemBarra: View {
    var situacao: Situacao
    var config: ConfigEstado
    var colorir: Bool
    var casas: Int
    var sentido: SentidoRitmo
    /// Desenho para virar imagem "template": tudo em preto, só o alfa importa.
    var modelo = false
    var escala: CGFloat = 1
    /// Cor das peças sem cor própria quando não há cor do estado (nas prévias, o texto do tema).
    var corBase: Color = .primary

    static let alturaBarra: CGFloat = 22
    /// Altura útil quando há pílula ou contorno.
    static let alturaComFundo: CGFloat = 18

    private var cor: Color {
        if modelo { return .black }
        if let hex = CorDaBarra.hex(estado: situacao.estado, situacao: situacao, config: config, colorir: colorir) {
            return Color(hex: hex)
        }
        return corBase
    }

    private func corDo(_ item: ItemPeca) -> Color {
        if modelo { return .black }
        if let hex = item.corHex { return CorDaBarra.ehBranco(hex) ? corBase : Color(hex: hex) }
        return cor
    }

    private var corFundo: Color {
        if modelo { return .black }
        if let hex = config.corFundoHex { return CorDaBarra.ehBranco(hex) ? corBase : Color(hex: hex) }
        return cor
    }

    private var comFundo: Bool { config.fundo != .nenhum }

    /// Com texto pequeno sobre a bateria, o valor ao lado fica maior (Empilhado).
    private var empilhado: Bool {
        config.pecas.contains { $0.peca == .tempoSobreBateria || $0.peca == .ritmoSobreBateria }
    }

    private func alturaDaLinha(_ itens: [ItemPeca], _ qual: LinhaPeca?) -> CGFloat {
        let design = config.fonte.design
        return itens.map { $0.alturaNatural(linha: qual, grande: empilhado && qual == nil, design: design) }.max() ?? 0
    }

    /// Fator que encolhe o conjunto quando a soma das alturas (com o tamanho geral) passa da altura útil.
    private var ajuste: CGFloat {
        let tg = CGFloat(config.tamanhoGeral)
        let total = (config.duasLinhas
            ? alturaDaLinha(config.pecas, .cima) + alturaDaLinha(config.pecasBaixo, .baixo) + CGFloat(config.espacoLinhas)
            : alturaDaLinha(config.pecas, nil)) * tg
        let util = comFundo ? Self.alturaComFundo : Self.alturaBarra
        return total > util ? util / total : 1
    }

    private func vista(_ item: ItemPeca, _ qual: LinhaPeca?, _ esc: CGFloat) -> some View {
        VistaPeca(peca: item.peca, situacao: situacao, cor: corDo(item), casas: casas, sentido: sentido,
                  grande: empilhado && qual == nil, linha: qual, escala: esc,
                  tamanho: item.tamanho, negrito: item.negrito, item: item)
            .offset(y: -CGFloat(item.deslocamentoY ?? 0) * esc)
    }

    private func linha(_ itens: [ItemPeca], _ qual: LinhaPeca, _ esc: CGFloat) -> some View {
        let espaco = config.espacoPecas.map { CGFloat($0) } ?? 3
        return HStack(alignment: config.alinhamentoVertical.vertical, spacing: espaco * esc) {
            ForEach(itens) { item in vista(item, qual, esc) }
        }
        .opacity(qual == .baixo ? 0.85 : 1)
        .frame(maxWidth: .infinity, alignment: config.alinhamento(em: qual).alinhamento)
    }

    private var conteudo: some View {
        let esc = escala * ajuste * CGFloat(config.tamanhoGeral)
        let minimo = config.larguraMinima.map { CGFloat($0) * escala }
        return Group {
            if config.duasLinhas {
                VStack(alignment: .leading, spacing: CGFloat(config.espacoLinhas) * esc) {
                    linha(config.pecas, .cima, esc)
                    linha(config.pecasBaixo, .baixo, esc)
                }
                .frame(minWidth: minimo, alignment: .leading)
            } else {
                let espaco = config.espacoPecas.map { CGFloat($0) } ?? 4
                HStack(alignment: config.alinhamentoVertical.vertical, spacing: espaco * esc) {
                    ForEach(config.pecas) { item in vista(item, nil, esc) }
                }
                .frame(minWidth: minimo, alignment: config.alinhamento(em: .cima).alinhamento)
            }
        }
    }

    @ViewBuilder
    private var comMoldura: some View {
        if comFundo {
            conteudo
                .padding(.horizontal, 4 * escala)
                .frame(height: Self.alturaComFundo * escala)
                .background {
                    if config.fundo == .pilula {
                        Capsule().fill(corFundo.opacity(0.25))
                    } else {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(corFundo, lineWidth: 1 * escala)
                    }
                }
        } else {
            conteudo
        }
    }

    var body: some View {
        Group {
            if config.oculto {
                Circle().fill(cor).frame(width: 5 * escala, height: 5 * escala)
            } else {
                comMoldura
            }
        }
        .environment(\.desenhoModelo, modelo)
        .environment(\.fonteDoItem, config.fonte.design)
        .frame(height: Self.alturaBarra * escala)
        .fixedSize()
    }
}

// MARK: - Imagem para o NSStatusItem

enum RenderizadorBarra {
    /// Renderiza o item em escala 2, 22 pt de altura. Sem cor, a imagem é template e desenhada em preto.
    @MainActor
    static func imagem(situacao: Situacao, config: ConfigEstado, colorir: Bool, casas: Int,
                       sentido: SentidoRitmo, escura: Bool) -> NSImage {
        // Cor do estado, cor própria de peça ou cor de fundo impedem o modo template (ele só tem alfa).
        // Fora do template, as peças sem cor seguem a aparência da barra: brancas na escura, escuras na clara.
        let comCorPropria = (config.pecas + config.pecasBaixo).contains { !CorDaBarra.ehBranco($0.corHex) }
        let semCorDoEstado = CorDaBarra.hex(estado: situacao.estado, situacao: situacao, config: config,
                                            colorir: colorir) == nil
        let modelo = semCorDoEstado && !comCorPropria && CorDaBarra.ehBranco(config.corFundoHex)
        let corBase: Color = escura ? .white : Color.black.opacity(0.85)
        let vista = VistaItemBarra(situacao: situacao, config: config, colorir: colorir, casas: casas,
                                   sentido: sentido, modelo: modelo, corBase: corBase)
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
    /// Atualização pelo GitHub; nil no build de desenvolvimento.
    var atualizador: Atualizador?
    private let pegarSituacao: () -> Situacao?
    private let abrirDetalhes: () -> Void
    private let abrirPreferencias: () -> Void
    private let abrirPreferenciasModulos: (() -> Void)?
    private let ajustesModulos: AjustesModulos
    private var observacaoAparencia: NSKeyValueObservation?
    private var ultimaEscura: Bool?
    /// Situação de exemplo por estado ("Ver na barra"), para não recalcular a série a cada redesenho.
    private var exemplos: [EstadoBarra: Situacao] = [:]

    private var barraEscura: Bool {
        statusItem.button?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    init(conteudoPainel: @escaping () -> AnyView,
         abrirDetalhes: @escaping () -> Void,
         abrirPreferencias: @escaping () -> Void,
         pegarSituacao: @escaping () -> Situacao?,
         abrirPreferenciasModulos: (() -> Void)? = nil,
         ajustesModulos: AjustesModulos = .compartilhado) {
        self.ajustesModulos = ajustesModulos
        self.pegarSituacao = pegarSituacao
        self.abrirPreferenciasModulos = abrirPreferenciasModulos
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
            ultimaEscura = barraEscura
            observacaoAparencia = botao.observe(\.effectiveAppearance) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.barraEscura != self.ultimaEscura else { return }
                    self.ultimaEscura = self.barraEscura
                    self.redesenhar()
                }
            }
        }
        redesenhar()
    }

    /// Lê a situação e os Ajustes e põe a imagem na barra. A T8 chama quando o Monitor muda.
    func redesenhar() {
        guard let botao = statusItem.button else { return }
        let ajustes = Ajustes.compartilhado
        // "Ver na barra": enquanto o editor pede, mostra a montagem daquele estado com uma situação de exemplo.
        if let previa = ajustes.estadoEmPrevia {
            let exemplo: Situacao
            if let guardado = exemplos[previa] { exemplo = guardado } else {
                exemplo = Situacao.exemplo(previa)
                exemplos[previa] = exemplo
            }
            botao.image = RenderizadorBarra.imagem(
                situacao: exemplo, config: ajustes.config(previa), colorir: ajustes.colorirBarra,
                casas: ajustes.casasDecimais, sentido: ajustes.sentido, escura: barraEscura)
            return
        }
        guard let situacao = pegarSituacao() else {
            let simbolo = NSImage(systemSymbolName: "battery.0", accessibilityDescription: "Sem bateria")
            simbolo?.isTemplate = true
            botao.image = simbolo
            return
        }
        botao.image = RenderizadorBarra.imagem(
            situacao: situacao, config: ajustes.config(situacao.estado), colorir: ajustes.colorirBarra,
            casas: ajustes.casasDecimais, sentido: ajustes.sentido, escura: barraEscura)
    }

    /// Esconde ou mostra o item da bateria (Preferências > Módulos).
    func definirVisivel(_ visivel: Bool) {
        if statusItem.isVisible != visivel { statusItem.isVisible = visivel }
    }

    /// Abre o popover da bateria se estiver fechado (usado pela Visão geral dos módulos).
    func abrirPopover() {
        guard !popover.isShown else { return }
        alternarPopover()
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
            TelaDoClique.compartilhada.usar(botao)
            popover.contentViewController?.view.layoutSubtreeIfNeeded()
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
        let salvos = Ajustes.compartilhado.formatosSalvos
        if !salvos.isEmpty {
            let submenu = NSMenu()
            for f in salvos {
                let item = NSMenuItem(title: f.nome, action: #selector(escolherSalvo(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = f.id
                submenu.addItem(item)
            }
            let pai = NSMenuItem(title: "Meus formatos", action: nil, keyEquivalent: "")
            pai.submenu = submenu
            menu.addItem(pai)
        }
        menu.addItem(.separator())
        let modulos = ajustesModulos
        let submodulos = NSMenu()
        for m in Modulo.allCases {
            let item = NSMenuItem(title: m.titulo, action: #selector(alternarModulo(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = m.rawValue
            item.state = modulos.ajuste(m).ligado ? .on : .off
            submodulos.addItem(item)
        }
        if abrirPreferenciasModulos != nil {
            submodulos.addItem(.separator())
            let prefs = NSMenuItem(title: "Preferências dos módulos…", action: #selector(chamarPreferenciasModulos), keyEquivalent: "")
            prefs.target = self
            submodulos.addItem(prefs)
        }
        let paiModulos = NSMenuItem(title: "Módulos do sistema", action: nil, keyEquivalent: "")
        paiModulos.submenu = submodulos
        menu.addItem(paiModulos)
        let detalhes = NSMenuItem(title: "Mais informações", action: #selector(chamarDetalhes), keyEquivalent: "")
        detalhes.target = self
        menu.addItem(detalhes)
        let preferencias = NSMenuItem(title: "Preferências…", action: #selector(chamarPreferencias), keyEquivalent: ",")
        preferencias.target = self
        menu.addItem(preferencias)
        if let a = atualizador, a.ligado {
            let titulo = a.pendente.map { "Atualizar para a versão \($0)…" } ?? "Procurar atualizações…"
            let item = NSMenuItem(title: titulo, action: #selector(chamarAtualizacao), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let sair = NSMenuItem(title: "Sair", action: #selector(sair), keyEquivalent: "q")
        sair.target = self
        menu.addItem(sair)

        // O menu só aparece preso ao botão enquanto estiver no statusItem.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func chamarAtualizacao() { atualizador?.buscarAgora() }

    @objc private func escolherFormato(_ item: NSMenuItem) {
        guard let bruto = item.representedObject as? String, let formato = FormatoBarra(rawValue: bruto) else { return }
        Ajustes.compartilhado.aplicar(formato)
        redesenhar()
    }

    @objc private func escolherSalvo(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID,
              let f = Ajustes.compartilhado.formatosSalvos.first(where: { $0.id == id }) else { return }
        Ajustes.compartilhado.aplicarSalvo(f)
        redesenhar()
    }

    @objc private func alternarModulo(_ item: NSMenuItem) {
        guard let bruto = item.representedObject as? String, let m = Modulo(rawValue: bruto) else { return }
        let ajustes = ajustesModulos
        ajustes.alternar(m, ligado: !ajustes.ajuste(m).ligado)
    }

    @objc private func chamarPreferenciasModulos() { abrirPreferenciasModulos?() }
    @objc private func chamarDetalhes() { abrirDetalhes() }
    @objc private func chamarPreferencias() { abrirPreferencias() }
    @objc private func sair() { NSApp.terminate(nil) }
}

// MARK: - Conferência (modo --foto)

@MainActor
enum FotoBarra {
    /// O item sobre uma faixa que imita a barra de menus escura de Main.dc.html, com a predefinição do formato.
    static func imagemDeConferencia(formato: FormatoBarra, estado: EstadoBarra, clara: Bool = false,
                                    colorir: Bool = false) -> NSImage {
        imagemDeConferencia(config: formato.config(para: estado, corHex: estado.corPadraoHex), estado: estado,
                            clara: clara, colorir: colorir)
    }

    /// O mesmo, com uma config qualquer (o exemplo montado à mão, por exemplo). `clara` usa uma barra clara.
    static func imagemDeConferencia(config: ConfigEstado, estado: EstadoBarra, clara: Bool = false,
                                    colorir: Bool = false) -> NSImage {
        let situacao = Situacao.exemplo(estado)
        // Como no desenho, só o consumo alto é colorido (a menos que se peça colorir); o resto segue a barra.
        let corBase: Color = clara ? Color.black.opacity(0.85) : .white
        let vista = VistaItemBarra(situacao: situacao, config: config, colorir: colorir, casas: 1, sentido: .sinais,
                                   corBase: corBase)
        let fundoFaixa: LinearGradient = clara
            ? LinearGradient(colors: [Color(hex: "#E9E4DC"), Color(hex: "#F6F2EA")], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color(hex: "#5A1E1C"), Color(hex: "#7A2A26")], startPoint: .topLeading, endPoint: .bottomTrailing)
        let faixa = ZStack(alignment: .topLeading) {
            fundoFaixa
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Text("13/11")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(clara ? Color.black.opacity(0.55) : Color.white.opacity(0.55))
                vista
                    .padding(.horizontal, 6)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(clara ? Color.white.opacity(0.7) : Color.white.opacity(0.16)))
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .frame(maxWidth: .infinity)
            .background(clara ? Color.clear : Color(red: 28 / 255, green: 18 / 255, blue: 16 / 255).opacity(0.55))
        }
        .frame(width: 250, height: 56)
        .environment(\.colorScheme, clara ? .light : .dark)
        let renderizador = ImageRenderer(content: faixa)
        renderizador.scale = 2
        guard let cg = renderizador.cgImage else { return NSImage() }
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
    }
}
