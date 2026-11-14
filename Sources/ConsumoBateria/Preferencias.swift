import SwiftUI
import UniformTypeIdentifiers

/// Quais seções a janela mostra: `.tudo` é a janela de sempre; as outras alimentam o menu lateral (PreferenciasMenu.swift).
enum SecaoPreferencias { case tudo, geral, bateria, temas, avisos }

/// Janela de Preferências (Preferencias.dc.html). Todos os controles são desenhados, sem Toggle, Picker nem
/// Stepper nativos, para o ImageRenderer gerar o PNG fiel. `paraFoto` tira a ScrollView e fixa a largura.
struct JanelaPreferencias: View {
    var ajustes: Ajustes
    var abrirAoIniciar: Bool
    var alternarAbrirAoIniciar: (Bool) -> Void
    var estadoInicial: EstadoBarra = .descarregando
    var paraFoto = false
    var pagina: SecaoPreferencias = .tudo
    /// Dentro de um container que já rola: sem ScrollView nem tamanho mínimo.
    var embutida = false

    @Environment(\.estilo) private var estilo
    @AppStorage(Ajustes.chaveTema) private var nomeTema = TemaApp.gold.rawValue
    @AppStorage(Ajustes.chaveCorNeon) private var neonHex = "#00F0FF"

    @State private var aberto: EstadoBarra?
    /// Peça em arrasto: o estado da linha de origem e o índice atual dela.
    @State private var arrastando: ArrastoPeca?
    /// Linha que a paleta aberta alimenta.
    @State private var linhaAberta: LinhaPeca = .cima
    /// Estados com a chave "Duas linhas" ligada ainda sem peça embaixo (a config só vira duas linhas com peça).
    @State private var editandoDuas: Set<EstadoBarra> = []
    /// Item com o popover "Ajustar peça" aberto.
    @State private var itemAberto: ItemAberto?
    /// Estados com o painel "Ajustes do item" aberto.
    @State private var ajustesAbertos: Set<EstadoBarra> = []
    /// Prévia sobre barra clara em vez de escura.
    @State private var previaClara = false
    /// Montagens anteriores (até 50) para desfazer e refazer.
    @State private var pilhaDesfazer: [Montagem] = []
    @State private var pilhaRefazer: [Montagem] = []
    /// Quando a última mudança foi empilhada: mudanças seguidas (arrasto do regulador) viram um passo só.
    @State private var ultimaMudanca: Date?

    /// O que desfazer e refazer guardam: o ladrilho de formato marcado e a montagem de cada estado.
    private struct Montagem {
        var formato: FormatoBarra
        var configs: [EstadoBarra: ConfigEstado]
    }

    private var montagemAtual: Montagem { Montagem(formato: ajustes.formatoBarra, configs: ajustes.configs) }

    private func restaurar(_ m: Montagem) {
        itemAberto = nil
        ultimaMudanca = nil
        ajustes.formatoBarra = m.formato
        ajustes.configs = m.configs
    }

    init(ajustes: Ajustes, abrirAoIniciar: Bool, alternarAbrirAoIniciar: @escaping (Bool) -> Void,
         estadoInicial: EstadoBarra = .descarregando, paraFoto: Bool = false,
         ajustesAbertosInicial: Set<EstadoBarra> = [], pagina: SecaoPreferencias = .tudo, embutida: Bool = false) {
        self.pagina = pagina
        self.embutida = embutida
        self.ajustes = ajustes
        self.abrirAoIniciar = abrirAoIniciar
        self.alternarAbrirAoIniciar = alternarAbrirAoIniciar
        self.estadoInicial = estadoInicial
        self.paraFoto = paraFoto
        _aberto = State(initialValue: estadoInicial)
        _ajustesAbertos = State(initialValue: ajustesAbertosInicial)
    }

    var body: some View {
        Group {
            if embutida {
                conteudo
            } else if paraFoto {
                conteudo.frame(width: 820)
            } else {
                ScrollView { conteudo }.frame(minWidth: 680, idealWidth: 820, minHeight: 520, idealHeight: 760)
            }
        }
    }

    private var conteudo: some View {
        VStack(alignment: .leading, spacing: 26) {
            switch pagina {
            case .tudo:
                secaoItem
                secaoRitmo
                secaoTema
                SecaoPainelPrefs(ajustes: ajustes)
                secaoAvisos(completa: true)
            case .bateria:
                secaoItem
                secaoRitmo
                SecaoPainelPrefs(ajustes: ajustes)
            case .temas:
                secaoTema
            case .avisos:
                secaoAvisos(completa: false)
            case .geral:
                secaoGeral
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Ao fechar a janela, o item da barra volta a mostrar o estado real.
        .onDisappear { ajustes.estadoEmPrevia = nil }
    }

    private func titulo(_ s: String) -> some View {
        Text(s).font(.system(size: 20, weight: .bold))
    }

    private func dica(_ s: String) -> some View {
        Text(s).font(.system(size: 13)).foregroundStyle(.secondary)
    }

    // MARK: Item da barra

    private var secaoItem: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    titulo("Item da barra de menus")
                    dica("Monte o desenho de cada estado. Clique numa peça para ajustá-la (texto, formato, tamanho, cor, altura, mover ou tirar); arraste para mudar a ordem. \"Ajustes do item\" mexe no item inteiro (espaços, fonte, fundo, largura, esconder). \"Meus formatos\" guarda e exporta a montagem; \"Ver na barra\" mostra o estado na barra de verdade enquanto você edita.")
                }
                Spacer(minLength: 8)
                botoesDesfazer
            }
            RotuloSecao("Formato")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(FormatoBarra.allCases) { formato in ladrilhoFormato(formato) }
            }
            RotuloSecao("Um desenho por estado")
            ForEach(EstadoBarra.allCases) { estado in linhaEstado(estado) }
            SecaoMeusFormatos(ajustes: ajustes, casas: ajustes.casasDecimais, sentido: ajustes.sentido,
                              paraFoto: paraFoto, antesDeMudar: { empilhar(agrupar: false) })
                .padding(.top, 8)
        }
    }

    // MARK: Desfazer e refazer

    private var botoesDesfazer: some View {
        HStack(spacing: 6) {
            if paraFoto {
                chipAcao("Desfazer", "arrow.uturn.backward", ativo: false) {}
                chipAcao("Refazer", "arrow.uturn.forward", ativo: false) {}
            } else {
                chipAcao("Desfazer", "arrow.uturn.backward", ativo: !pilhaDesfazer.isEmpty, desfazer)
                chipAcao("Refazer", "arrow.uturn.forward", ativo: !pilhaRefazer.isEmpty, refazer)
            }
        }
        .background {
            // Atalhos ⌘Z e ⇧⌘Z (o app não tem menu Editar). Com um campo de texto em edição, valem para o texto.
            if !paraFoto {
                ZStack {
                    Button("") { atalhoDesfazer(refazer: false) }.keyboardShortcut("z")
                    Button("") { atalhoDesfazer(refazer: true) }.keyboardShortcut("z", modifiers: [.command, .shift])
                }
                .opacity(0).frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }

    /// Há um campo de texto em edição na janela (o editor de campo do AppKit é um NSText).
    private var editandoTexto: Bool { NSApp.keyWindow?.firstResponder is NSText }

    private func atalhoDesfazer(refazer: Bool) {
        if editandoTexto {
            // Deixa o campo desfazer o próprio texto; a montagem não muda.
            NSApp.sendAction(Selector(refazer ? "redo:" : "undo:"), to: nil, from: nil)
        } else if refazer {
            self.refazer()
        } else {
            desfazer()
        }
    }

    private func chipAcao(_ titulo: String, _ simbolo: String, ativo: Bool = true, selecionado: Bool = false,
                          _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            HStack(spacing: 5) {
                Image(systemName: simbolo).font(.system(size: 11, weight: .semibold))
                Text(titulo).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(selecionado ? estilo.primeiroPlanoSelecionado : Color.primary.opacity(0.85))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background {
                if selecionado { FundoSelecionavel(selecionado: true, capsula: true) }
                else { Capsule().fill(Color.primary.opacity(0.08)) }
            }
            .opacity(ativo ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!ativo)
        .accessibilityLabel(titulo)
        .accessibilityAddTraits(selecionado ? .isSelected : [])
    }

    /// Guarda a montagem de agora antes de uma mudança. Com `agrupar`, mudanças a menos de 0,6 s da anterior
    /// (o arrasto de um regulador) não abrem um passo novo.
    private func empilhar(agrupar: Bool = true) {
        let agora = Date()
        defer { ultimaMudanca = agrupar ? agora : nil }
        if agrupar, let ultima = ultimaMudanca, agora.timeIntervalSince(ultima) < 0.6 { return }
        pilhaDesfazer.append(montagemAtual)
        if pilhaDesfazer.count > 50 { pilhaDesfazer.removeFirst(pilhaDesfazer.count - 50) }
        pilhaRefazer = []
    }

    private func desfazer() {
        guard let anterior = pilhaDesfazer.popLast() else { return }
        pilhaRefazer.append(montagemAtual)
        restaurar(anterior)
    }

    private func refazer() {
        guard let proximo = pilhaRefazer.popLast() else { return }
        pilhaDesfazer.append(montagemAtual)
        restaurar(proximo)
    }

    private func ladrilhoFormato(_ formato: FormatoBarra) -> some View {
        let selecionado = ajustes.formatoBarra == formato
        let hex = selecionado ? estilo.primeiroPlanoSelecionado.hexString : (estilo.texto?.hexString ?? "#F5F5F5")
        let cfg = formato.config(para: .descarregando, corHex: hex)
        return Button { empilhar(agrupar: false); ajustes.aplicar(formato) } label: {
            VStack(spacing: 8) {
                VistaItemBarra(situacao: .exemplo(.descarregando), config: cfg, colorir: true,
                               casas: ajustes.casasDecimais, sentido: ajustes.sentido)
                    .frame(maxWidth: .infinity, minHeight: 30)
                Text(formato.titulo)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selecionado ? estilo.primeiroPlanoSelecionado : Color.primary)
            }
            .padding(.vertical, 10).padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(FundoSelecionavel(selecionado: selecionado, raio: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selecionado ? .isSelected : [])
    }

    private func emDuas(_ estado: EstadoBarra, _ cfg: ConfigEstado) -> Bool {
        cfg.duasLinhas || editandoDuas.contains(estado)
    }

    private func linhaEstado(_ estado: EstadoBarra) -> some View {
        let cfg = ajustes.config(estado)
        let cor = Color(hex: cfg.corHex)
        let situacao = Situacao.exemplo(estado)
        let isAberto = aberto == estado
        let duas = emDuas(estado, cfg)
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Circle().fill(cor).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(estado.titulo).font(.system(size: 15, weight: .semibold))
                            if cfg.oculto {
                                Text("escondido").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.primary.opacity(0.1)))
                            }
                        }
                        Text(estado.dica).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if !duas {
                        listaPecas(estado: estado, linha: .cima, cfg: cfg, situacao: situacao)
                    }
                    chaveDuasLinhas(estado, ligada: duas)
                    Button { aberto = isAberto ? nil : estado } label: {
                        Circle().fill(cor).frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cor de \(estado.titulo)")
                    if !duas { botaoMais(estado, .cima, aberto: isAberto, rotulo: "Adicionar peça em \(estado.titulo)") }
                }
                if duas {
                    faixaDaLinha("Linha de cima", estado: estado, linha: .cima, cfg: cfg, situacao: situacao, isAberto: isAberto)
                    faixaDaLinha("Linha de baixo", estado: estado, linha: .baixo, cfg: cfg, situacao: situacao, isAberto: isAberto)
                }
                rodapeEstado(estado, cfg: cfg, situacao: situacao, duas: duas)
                if isAberto { faixaAcoes(estado, cfg: cfg) }
                if isAberto, ajustesAbertos.contains(estado) {
                    PainelItemEstado(config: cfg, estado: estado, cores: Self.coresDaPaleta(estado), paraFoto: paraFoto) { novo in
                        empilhar()
                        ajustes.configs[estado] = novo
                    }
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(estilo.ladrilho.opacity(0.5)))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.cartao))
            .overlay {
                if isAberto {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(estilo.destaque.opacity(0.55), lineWidth: 1)
                }
            }
            if isAberto { paleta(estado: estado, cfg: cfg, situacao: situacao) }
        }
    }

    /// Ações do estado aberto: ajustes do item, copiar, restaurar, ver na barra e fundo da prévia.
    private func faixaAcoes(_ estado: EstadoBarra, cfg: ConfigEstado) -> some View {
        let ajustesAbertosAqui = ajustesAbertos.contains(estado)
        let emPrevia = ajustes.estadoEmPrevia == estado
        let outros = EstadoBarra.allCases.filter { $0 != estado }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                chipAcao("Ajustes do item", "slider.horizontal.3", selecionado: ajustesAbertosAqui) {
                    if ajustesAbertosAqui { ajustesAbertos.remove(estado) } else { ajustesAbertos.insert(estado) }
                }
                if paraFoto {
                    chipAcao("Copiar para…", "doc.on.doc") {}
                } else {
                    Menu {
                        ForEach(outros) { destino in
                            Button(destino.titulo) { copiar(de: estado, para: [destino]) }
                        }
                        Divider()
                        Button("Todos os outros") { copiar(de: estado, para: outros) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.on.doc").font(.system(size: 11, weight: .semibold))
                            Text("Copiar para…").font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .accessibilityLabel("Copiar a montagem de \(estado.titulo) para outro estado")
                }
                chipAcao("Restaurar predefinição", "arrow.counterclockwise") {
                    empilhar(agrupar: false)
                    ajustesAbertos.remove(estado)
                    editandoDuas.remove(estado)
                    ajustes.restaurarPredefinicao(estado)
                }
                Spacer(minLength: 8)
            }
            HStack(spacing: 6) {
                chipAcao("Ver na barra", "menubar.rectangle", selecionado: emPrevia) {
                    ajustes.estadoEmPrevia = emPrevia ? nil : estado
                }
                Spacer(minLength: 8)
                Text("Prévia").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach([false, true], id: \.self) { clara in
                        let sel = previaClara == clara
                        Button { previaClara = clara } label: {
                            Text(clara ? "Clara" : "Escura")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(sel ? estilo.primeiroPlanoSelecionado : Color.primary.opacity(0.75))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(FundoSelecionavel(selecionado: sel, capsula: true))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Prévia em barra \(clara ? "clara" : "escura")")
                        .accessibilityAddTraits(sel ? .isSelected : [])
                    }
                }
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(estilo.ladrilho))
            }
        }
    }

    private func copiar(de origem: EstadoBarra, para destinos: [EstadoBarra]) {
        empilhar(agrupar: false)
        ajustes.copiarMontagem(de: origem, para: destinos)
    }

    private func faixaDaLinha(_ nome: String, estado: EstadoBarra, linha: LinhaPeca, cfg: ConfigEstado,
                              situacao: Situacao, isAberto: Bool) -> some View {
        HStack(spacing: 12) {
            Text(nome).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            chipsAlinhamento(estado, linha, cfg: cfg)
            Spacer(minLength: 8)
            listaPecas(estado: estado, linha: linha, cfg: cfg, situacao: situacao)
            botaoMais(estado, linha, aberto: isAberto && linhaAberta == linha, rotulo: "Adicionar peça na \(nome.lowercased()) de \(estado.titulo)")
        }
    }

    /// Prévia em 2× sobre fundo de barra; com duas linhas, o espaço entre elas; com uma, o alinhamento.
    private func rodapeEstado(_ estado: EstadoBarra, cfg: ConfigEstado, situacao: Situacao, duas: Bool) -> some View {
        HStack(spacing: 12) {
            Text("Prévia").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            previa(cfg, situacao)
            Spacer(minLength: 8)
            if duas {
                Text("Espaço entre linhas").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                botaoPasso("minus", rotulo: "Diminuir espaço entre linhas") { mudarEspaco(estado, -0.5) }
                Text(Self.numeroSinal(cfg.espacoLinhas) + " pt").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    .frame(minWidth: 56)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(estilo.ladrilho))
                botaoPasso("plus", rotulo: "Aumentar espaço entre linhas") { mudarEspaco(estado, 0.5) }
            } else {
                Text("Alinhamento").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                VStack(alignment: .trailing, spacing: 3) {
                    chipsAlinhamento(estado, .cima, cfg: cfg)
                    if cfg.larguraMinima == nil {
                        Text("vale com largura mínima").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// O item da barra em escala 2 sobre um fundo escuro de barra de menus.
    private func previa(_ cfg: ConfigEstado, _ situacao: Situacao) -> some View {
        VistaItemBarra(situacao: situacao, config: cfg, colorir: true, casas: ajustes.casasDecimais,
                       sentido: ajustes.sentido, escala: 2, corBase: previaClara ? Color.black.opacity(0.85) : .white)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(previaClara ? Color(hex: "#ECE7DF") : Color.black.opacity(0.6)))
            .environment(\.colorScheme, previaClara ? .light : .dark)
    }

    private func chipsAlinhamento(_ estado: EstadoBarra, _ linha: LinhaPeca, cfg: ConfigEstado) -> some View {
        let atual = cfg.alinhamento(em: linha)
        return HStack(spacing: 4) {
            ForEach(AlinhamentoLinha.allCases) { a in
                let sel = a == atual
                Button { atualizar(estado) { $0.definirAlinhamento(a, em: linha) } } label: {
                    Image(systemName: a.simbolo)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 24)
                        .foregroundStyle(sel ? estilo.primeiroPlanoSelecionado : Color.primary.opacity(0.75))
                        .background(FundoSelecionavel(selecionado: sel, capsula: true))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Alinhar à \(a.titulo.lowercased())")
                .accessibilityAddTraits(sel ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(estilo.ladrilho))
    }

    private func mudarEspaco(_ estado: EstadoBarra, _ delta: Double) {
        atualizar(estado) { $0.espacoLinhas = min(4, max(-2, $0.espacoLinhas + delta)) }
    }

    static func numeroSinal(_ v: Double) -> String {
        let n = v.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "pt_BR")))
        let t = v > 0 ? "+" + n : n.replacingOccurrences(of: "-", with: "−")
        return t
    }

    private func botaoMais(_ estado: EstadoBarra, _ linha: LinhaPeca, aberto isAberto: Bool, rotulo: String) -> some View {
        Button {
            if isAberto { aberto = nil } else { aberto = estado; linhaAberta = linha }
        } label: {
            Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.primary.opacity(isAberto ? 0.18 : 0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rotulo)
    }

    private func chaveDuasLinhas(_ estado: EstadoBarra, ligada: Bool) -> some View {
        Button { alternarDuasLinhas(estado, ligar: !ligada) } label: {
            Text("Duas linhas")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ligada ? estilo.primeiroPlanoSelecionado : Color.primary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(ligada ? estilo.destaque : Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Duas linhas em \(estado.titulo)")
        .accessibilityAddTraits(ligada ? .isSelected : [])
    }

    private func listaPecas(estado: EstadoBarra, linha: LinhaPeca, cfg: ConfigEstado, situacao: Situacao) -> some View {
        let cor = Color(hex: cfg.corHex)
        let pecas = cfg.pecas(em: linha)
        return HStack(spacing: 2) {
            if pecas.isEmpty {
                Text("vazia").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(Array(pecas.enumerated()), id: \.element.id) { i, item in
                let miniatura = MiniaturaPeca(peca: item.peca, situacao: situacao,
                                              cor: item.corHex.map { Color(hex: $0) } ?? cor,
                                              casas: ajustes.casasDecimais, sentido: ajustes.sentido,
                                              mostrarTitulo: false, negrito: item.negrito, item: item)
                    .padding(.horizontal, 3)
                    .frame(minHeight: 30)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(item.personalizado ? estilo.destaque.opacity(0.7) : Color.primary.opacity(0.18),
                                      style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                if paraFoto {
                    miniatura
                } else {
                    Button { itemAberto = ItemAberto(estado: estado, linha: linha, id: item.id) } label: { miniatura }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Ajustar \(item.peca.titulo)")
                        .popover(isPresented: popover(estado, linha, item.id), arrowEdge: .bottom) {
                            painelAjuste(estado: estado, linha: linha, id: item.id)
                        }
                        .onDrag {
                            arrastando = ArrastoPeca(estado: estado, linha: linha, indice: i)
                            return NSItemProvider(object: item.peca.rawValue as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: SoltarPeca(
                            estado: estado, linha: linha, alvo: i, arrastando: $arrastando,
                            mover: { de, para in mover(de, para, em: estado, linha) }))
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(minWidth: 60, minHeight: 34, alignment: .trailing)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(estilo.scheme == .light ? 0.06 : 0.28)))
        // Soltar fora de uma peça (no fundo da linha) também encerra o arrasto.
        .modifier(SoltarNoFundo(ativo: !paraFoto) { arrastando = nil })
    }

    private func popover(_ estado: EstadoBarra, _ linha: LinhaPeca, _ id: UUID) -> Binding<Bool> {
        let alvo = ItemAberto(estado: estado, linha: linha, id: id)
        return Binding(get: { itemAberto == alvo }, set: { if !$0, itemAberto == alvo { itemAberto = nil } })
    }

    @ViewBuilder
    private func painelAjuste(estado: EstadoBarra, linha: LinhaPeca, id: UUID) -> some View {
        let cfg = ajustes.config(estado)
        let lista = cfg.pecas(em: linha)
        if let i = lista.firstIndex(where: { $0.id == id }) {
            let duas = emDuas(estado, cfg)
            PainelAjustarPeca(
                item: lista[i], cores: Self.coresDaPaleta(estado),
                tamanhoAuto: Double(VistaPeca.tamanhoAutomatico(linha: duas ? linha : nil, grande: !duas && cfg.empilhado)),
                negritoAuto: !duas || linha == .cima,
                duasLinhas: duas, podeEsquerda: i > 0, podeDireita: i < lista.count - 1,
                mudar: { novo in ajustarItem(novo, em: estado, linha) },
                moverEsquerda: { mover(i, i - 1, em: estado, linha) },
                moverDireita: { mover(i, i + 1, em: estado, linha) },
                outraLinha: { paraOutraLinha(id, em: estado, linha) },
                tirar: { tirar(id, de: estado, linha) },
                situacao: Situacao.exemplo(estado), casasGlobal: ajustes.casasDecimais, sentidoGlobal: ajustes.sentido)
        }
    }

    private func paleta(estado: EstadoBarra, cfg: ConfigEstado, situacao: Situacao) -> some View {
        let cor = Color(hex: cfg.corHex)
        let unicas = Self.coresDaPaleta(estado)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RotuloSecao(emDuas(estado, cfg) ? "Adicionar em \(estado.titulo), \(linhaAberta == .cima ? "linha de cima" : "linha de baixo")" : "Adicionar em \(estado.titulo)")
                Spacer()
                Text("Prévia").font(.system(size: 11)).foregroundStyle(.secondary)
                previa(cfg, situacao)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(Peca.allCases.filter { $0 != .ritmoWatts }) { peca in
                    Button { acrescentar(ItemPeca(peca), em: estado, linhaAberta) } label: {
                        HStack(spacing: 10) {
                            MiniaturaPeca(peca: peca, situacao: situacao, cor: cor, casas: ajustes.casasDecimais,
                                          sentido: ajustes.sentido, mostrarTitulo: false)
                                .scaleEffect(0.8)
                                .frame(width: 74, height: 30)
                                .clipped()
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.black.opacity(estilo.scheme == .light ? 0.06 : 0.28)))
                            Text(peca.titulo).font(.system(size: 13)).lineLimit(2).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(estilo.ladrilho))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                Text("Cor").font(.system(size: 12)).foregroundStyle(.secondary)
                ForEach(unicas, id: \.self) { hex in
                    let sel = hex.uppercased() == cfg.corHex.uppercased()
                    Button { definirCor(hex, em: estado) } label: {
                        Circle().fill(Color(hex: hex)).frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(sel ? estilo.destaque : Color.primary.opacity(0.25), lineWidth: sel ? 2.5 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cor \(hex)")
                }
                Spacer()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.cartao))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(estilo.destaque.opacity(0.35), lineWidth: 1))
        .padding(.leading, 24)
    }

    // MARK: Edição das listas

    private func atualizar(_ estado: EstadoBarra, _ mudar: (inout ConfigEstado) -> Void) {
        empilhar()
        var c = ajustes.config(estado)
        mudar(&c)
        ajustes.configs[estado] = c
    }

    /// As cores da paleta de um estado (a do estado primeiro, sem repetir).
    static func coresDaPaleta(_ estado: EstadoBarra) -> [String] {
        let amostras = [estado.corPadraoHex, "#34C759", "#E0B357", "#FFFFFF", "#BF5AF2", "#FF9F0A", "#0A84FF", "#FF453A", "#00F0FF"]
        var unicas: [String] = []
        for h in amostras where !unicas.contains(h) { unicas.append(h) }
        return unicas
    }

    private func tirar(_ id: UUID, de estado: EstadoBarra, _ linha: LinhaPeca) {
        itemAberto = nil
        atualizar(estado) { c in
            c.alterar(linha) { $0.removeAll { $0.id == id } }
        }
    }

    private func ajustarItem(_ novo: ItemPeca, em estado: EstadoBarra, _ linha: LinhaPeca) {
        atualizar(estado) { c in
            c.alterar(linha) { lista in
                if let i = lista.firstIndex(where: { $0.id == novo.id }) { lista[i] = novo }
            }
        }
    }

    /// Passa o item para o fim da outra linha.
    private func paraOutraLinha(_ id: UUID, em estado: EstadoBarra, _ linha: LinhaPeca) {
        itemAberto = nil
        editandoDuas.insert(estado)
        atualizar(estado) { c in
            var levado: ItemPeca?
            c.alterar(linha) { lista in
                if let i = lista.firstIndex(where: { $0.id == id }) { levado = lista.remove(at: i) }
            }
            if let levado { c.alterar(linha == .cima ? .baixo : .cima) { $0.append(levado) } }
        }
    }

    private func acrescentar(_ item: ItemPeca, em estado: EstadoBarra, _ linha: LinhaPeca) {
        atualizar(estado) { $0.alterar(linha) { $0.append(item) } }
    }

    private func mover(_ de: Int, _ para: Int, em estado: EstadoBarra, _ linha: LinhaPeca) {
        atualizar(estado) { c in
            c.alterar(linha) {
                guard $0.indices.contains(de), $0.indices.contains(para) else { return }
                $0.move(fromOffsets: [de], toOffset: para > de ? para + 1 : para)
            }
        }
    }

    /// Ligar abre a faixa de baixo (vazia até entrar uma peça); desligar junta tudo numa linha só.
    private func alternarDuasLinhas(_ estado: EstadoBarra, ligar: Bool) {
        if ligar {
            editandoDuas.insert(estado)
            linhaAberta = .baixo
            aberto = estado
        } else {
            editandoDuas.remove(estado)
            linhaAberta = .cima
            atualizar(estado) {
                $0.pecas += $0.pecasBaixo
                $0.pecasBaixo = []
            }
        }
    }

    private func definirCor(_ hex: String, em estado: EstadoBarra) {
        atualizar(estado) { $0.corHex = hex }
    }

    // MARK: Ritmo

    private var secaoRitmo: some View {
        VStack(alignment: .leading, spacing: 12) {
            titulo("Ritmo")
            linhaSegmentada("Calcular pela média de", "Média curta reage rápido; longa fica estável", largura: 250) {
                LinhaChips(opcoes: MediaRitmo.allCases.map { .init(valor: $0, titulo: $0.titulo) },
                           selecao: ajustes.mediaRitmo) { ajustes.mediaRitmo = $0 }
            }
            linhaSegmentada("Casas decimais", "−11 %/h ou −11,3 %/h", largura: 110) {
                LinhaChips(opcoes: [.init(valor: 0, titulo: "0"), .init(valor: 1, titulo: "1")],
                           selecao: ajustes.casasDecimais) { ajustes.casasDecimais = $0 }
            }
            linhaSegmentada("Indicar o sentido com", "Saindo ou entrando energia", largura: 250) {
                LinhaChips(opcoes: SentidoRitmo.allCases.map { .init(valor: $0, titulo: $0.titulo) },
                           selecao: ajustes.sentido) { ajustes.sentido = $0 }
            }
            Cartao(padding: 0) {
                VStack(spacing: 0) {
                    LinhaAlternar(titulo: "Colorir a barra conforme o estado", ligado: ajustes.colorirBarra) {
                        ajustes.colorirBarra = $0
                    }
                    divisor
                    linhaLimite("Consumo alto a partir de", valor: "\(Int(ajustes.limiteAlto)) %/h") {
                        ajustes.limiteAlto = min(60, max(5, ajustes.limiteAlto + Double($0)))
                    }
                }
                .padding(.horizontal, 14)
            }
        }
    }

    private func linhaSegmentada<C: View>(_ rotulo: String, _ ajuda: String, largura: CGFloat,
                                          @ViewBuilder controle: () -> C) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rotulo).font(.system(size: 14))
                Text(ajuda).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            controle()
                .frame(width: largura)
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(estilo.ladrilho))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.cartao))
    }

    private var divisor: some View {
        Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
    }

    /// Linha com título, limite ajustável por − / + desenhados.
    private func linhaLimite(_ rotulo: String, valor: String, mudar: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(rotulo).font(.system(size: 14))
            Spacer(minLength: 8)
            botaoPasso("minus", rotulo: "Diminuir") { mudar(-1) }
            Text(valor).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                .frame(minWidth: 64)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(estilo.ladrilho))
            botaoPasso("plus", rotulo: "Aumentar") { mudar(1) }
        }
        .frame(minHeight: 48)
    }

    private func botaoPasso(_ simbolo: String, rotulo: String, acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: simbolo).font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(estilo.ladrilho))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rotulo)
    }

    // MARK: Tema

    private var secaoTema: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                titulo("Tema")
                Spacer()
                dica("Os mesmos do Budsmith")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                ForEach(TemaApp.allCases) { tema in ladrilhoTema(tema) }
            }
            if estilo.ehNeon { linhaNeon }
        }
    }

    private func ladrilhoTema(_ tema: TemaApp) -> some View {
        let selecionado = estilo.tema == tema
        let e = EstiloTema.make(tema, neon: Color(hex: neonHex))
        return Button { nomeTema = tema.rawValue } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fundoAmostra(tema, e))
                    .frame(width: 52, height: 52)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tema == .neon ? AnyShapeStyle(e.destaque)
                                  : tema == .vidro ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "#7FD3F7"), Color(hex: "#8A7CF0"), Color(hex: "#F59BC4")], startPoint: .topLeading, endPoint: .bottomTrailing))
                                  : AnyShapeStyle(e.degrade))
                            .frame(width: 24, height: 24)
                    }
                Text(tema.titulo).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.vertical, 12).padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.cartao))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selecionado ? estilo.destaque : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selecionado ? .isSelected : [])
    }

    private func fundoAmostra(_ tema: TemaApp, _ e: EstiloTema) -> Color {
        tema == .vidro ? Color.white.opacity(0.12) : (e.fundo ?? .black)
    }

    private var linhaNeon: some View {
        let cores = ["#00F0FF", "#39FF14", "#FF2BD6", "#FFE600", "#FF6A00", "#9D4DFF"]
        return HStack(spacing: 10) {
            Text("Cor do Neon").font(.system(size: 14))
            Spacer()
            ForEach(cores, id: \.self) { hex in
                let sel = hex.uppercased() == neonHex.uppercased()
                Button { neonHex = hex } label: {
                    Circle().fill(Color(hex: hex)).frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(sel ? Color.white : Color.white.opacity(0.25), lineWidth: sel ? 2.5 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Neon \(hex)")
            }
            if !paraFoto {
                ColorPicker("Outra cor", selection: Binding(get: { Color(hex: neonHex) },
                                                             set: { neonHex = $0.hexString }), supportsOpacity: false)
                    .labelsHidden()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.cartao))
    }

    // MARK: Avisos e geral

    private func secaoAvisos(completa: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            titulo(completa ? "Avisos e geral" : "Avisos")
            Cartao(padding: 0) {
                VStack(spacing: 0) {
                    avisoLinha("Avisar quando o consumo passar de", ajustes.avisoConsumoAcima, sufixo: " %/h", passo: 1, faixa: 5...60) {
                        ajustes.avisoConsumoAcima = $0
                    }
                    divisor
                    avisoLinha("Avisar quando a bateria ficar abaixo de", ajustes.avisoBateriaAbaixo, sufixo: "%", passo: 1, faixa: 5...50) {
                        ajustes.avisoBateriaAbaixo = $0
                    }
                    divisor
                    avisoLinha("Avisar quando carregar até", ajustes.avisoCarregouAte, sufixo: "%", passo: 5, faixa: 50...100) {
                        ajustes.avisoCarregouAte = $0
                    }
                    divisor
                    avisoLinha("Avisar se o carregador for fraco (menos de)", ajustes.avisoCarregadorFraco, sufixo: " W", passo: 5, faixa: 5...100) {
                        ajustes.avisoCarregadorFraco = $0
                    }
                    if completa {
                        divisor
                        linhaGeralAbrir
                        divisor
                        linhaHistorico
                    }
                }
                .padding(.horizontal, 14)
            }
        }
    }

    private var linhaGeralAbrir: some View {
        LinhaAlternar(titulo: "Abrir ao iniciar o Mac", ligado: abrirAoIniciar, aoMudar: alternarAbrirAoIniciar)
    }

    private var secaoGeral: some View {
        VStack(alignment: .leading, spacing: 12) {
            titulo("Geral")
            Cartao(padding: 0) {
                VStack(spacing: 0) {
                    linhaGeralAbrir
                    divisor
                    linhaHistorico
                }
                .padding(.horizontal, 14)
            }
        }
    }

    private func avisoLinha(_ rotulo: String, _ aviso: Aviso, sufixo: String, passo: Int, faixa: ClosedRange<Int>,
                            gravar: @escaping (Aviso) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(rotulo).font(.system(size: 14))
            Spacer(minLength: 8)
            botaoPasso("minus", rotulo: "Diminuir limite") { gravar(ajustado(aviso, -passo, faixa)) }
            Text("\(Int(aviso.limite))\(sufixo)").font(.system(size: 14, weight: .semibold)).monospacedDigit()
                .frame(minWidth: 64)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(estilo.ladrilho))
            botaoPasso("plus", rotulo: "Aumentar limite") { gravar(ajustado(aviso, passo, faixa)) }
            ChaveFina(ligado: aviso.ligado) { gravar(Aviso(ligado: $0, limite: aviso.limite)) }
                .accessibilityLabel(rotulo)
        }
        .frame(minHeight: 48)
    }

    private func ajustado(_ aviso: Aviso, _ delta: Int, _ faixa: ClosedRange<Int>) -> Aviso {
        let novo = min(faixa.upperBound, max(faixa.lowerBound, Int(aviso.limite) + delta))
        return Aviso(ligado: aviso.ligado, limite: Double(novo))
    }

    private var linhaHistorico: some View {
        HStack(spacing: 12) {
            Text("Guardar histórico por").font(.system(size: 14))
            Spacer(minLength: 8)
            LinhaChips(opcoes: [30, 90, 180].map { .init(valor: $0, titulo: "\($0) dias") },
                       selecao: ajustes.diasHistorico) { ajustes.diasHistorico = $0 }
                .frame(width: 250)
        }
        .frame(minHeight: 48)
    }
}

// MARK: - Arrastar para reordenar

private struct ItemAberto: Equatable {
    var estado: EstadoBarra
    var linha: LinhaPeca
    var id: UUID
}

private struct ArrastoPeca: Equatable {
    var estado: EstadoBarra
    var linha: LinhaPeca
    var indice: Int
}

private struct SoltarPeca: DropDelegate {
    let estado: EstadoBarra
    let linha: LinhaPeca
    let alvo: Int
    @Binding var arrastando: ArrastoPeca?
    let mover: (Int, Int) -> Void

    func dropEntered(info: DropInfo) {
        // Solta sobre outro estado ou outra linha: ignora.
        guard let atual = arrastando, atual.estado == estado, atual.linha == linha, atual.indice != alvo else { return }
        mover(atual.indice, alvo)
        arrastando = ArrastoPeca(estado: estado, linha: linha, indice: alvo)
    }

    func dropExited(info: DropInfo) {}

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        arrastando = nil
        return true
    }
}

/// Soltar no fundo da faixa encerra o arrasto. Fora do modo --foto apenas: o ImageRenderer desenha um
/// aviso amarelo no lugar de views com onDrop.
private struct SoltarNoFundo: ViewModifier {
    let ativo: Bool
    let aoSoltar: () -> Void

    func body(content: Content) -> some View {
        if ativo {
            content.onDrop(of: [UTType.text], isTargeted: nil) { _ in
                aoSoltar()
                return false
            }
        } else {
            content
        }
    }
}

// MARK: - Popover "Ajustar peça"

extension ConfigEstado {
    /// Há texto pequeno sobre a bateria na linha única (o valor ao lado fica em 16 pt).
    fileprivate var empilhado: Bool {
        pecas.contains { $0.peca == .tempoSobreBateria || $0.peca == .ritmoSobreBateria }
    }
}

/// Altura do conteúdo do painel, para a ScrollView do popover só rolar quando passar do limite.
private struct AlturaPainel: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Conteúdo que rola só quando passa do limite de altura (o popover fica do tamanho do conteúdo até lá).
private struct RolagemLimitada<Conteudo: View>: View {
    let limite: CGFloat
    @ViewBuilder let conteudo: () -> Conteudo
    @State private var altura: CGFloat = 520

    var body: some View {
        ScrollView {
            conteudo().background(GeometryReader { g in Color.clear.preference(key: AlturaPainel.self, value: g.size.height) })
        }
        .onPreferenceChange(AlturaPainel.self) { altura = $0 }
        .frame(height: min(max(altura, 120), limite))
    }
}

/// O que se ajusta numa peça: tamanho, peso, cor, altura, texto, formato, símbolo, posição e remoção.
/// Abre como popover ao clicar na peça. Sem controle que dependa do ImageRenderer fora do `paraFoto`.
struct PainelAjustarPeca: View {
    @Environment(\.estilo) private var estilo
    let item: ItemPeca
    let cores: [String]
    /// Tamanho (pt) e peso que a linha dá quando nada foi escolhido.
    let tamanhoAuto: Double
    let negritoAuto: Bool
    let duasLinhas: Bool
    let podeEsquerda: Bool
    let podeDireita: Bool
    /// Recebe o item já alterado.
    let mudar: (ItemPeca) -> Void
    let moverEsquerda: () -> Void
    let moverDireita: () -> Void
    let outraLinha: () -> Void
    let tirar: () -> Void
    /// Situação de exemplo da mini prévia no topo; nil esconde a prévia.
    var situacao: Situacao? = nil
    var casasGlobal = 1
    var sentidoGlobal: SentidoRitmo = .sinais
    /// Gerando PNG: campos de texto viram texto estático e a ScrollView some.
    var paraFoto = false

    private func alterar(_ f: (inout ItemPeca) -> Void) {
        var novo = item
        f(&novo)
        mudar(novo)
    }

    private func numero(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "pt_BR")))
    }

    private var peca: Peca { item.peca }
    private var temTexto: Bool {
        [.ritmo, .porcentagem, .tempo, .horario, .watts, .texto, .ritmoSobreBateria, .tempoSobreBateria].contains(peca)
    }
    private var temCasas: Bool { [.ritmo, .watts, .ritmoSobreBateria, .texto].contains(peca) }
    private var temUnidade: Bool { [.ritmo, .porcentagem, .watts, .ritmoSobreBateria, .texto].contains(peca) }
    private var temSinal: Bool { [.ritmo, .ritmoSobreBateria, .texto].contains(peca) }
    private var temTempo: Bool { [.tempo, .tempoSobreBateria, .texto].contains(peca) }

    var body: some View {
        Group {
            if paraFoto {
                miolo
            } else {
                RolagemLimitada(limite: 620) { miolo }
            }
        }
        .frame(width: 360)
    }

    private var miolo: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ajustar peça").font(.system(size: 15, weight: .bold))
                Text(item.peca.titulo).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let situacao { miniPrevia(situacao) }
            if peca == .texto { secaoTextoLivre }
            if peca == .etiquetaValor {
                campo("Etiqueta") {
                    caixa("BAT", Binding(get: { item.texto ?? "" },
                                         set: { v in alterar { $0.texto = v.isEmpty ? nil : String(v.prefix(ItemPeca.limiteTexto)) } }))
                }
            }
            if temTexto {
                campo("Antes") { caixa("ex.: ~", textoOpcional(\.prefixo)) }
                campo("Depois") { caixa("ex.: h", textoOpcional(\.sufixo)) }
            }
            campo("Tamanho") {
                HStack(spacing: 8) {
                    chip("Automático", selecionado: item.tamanho == nil) { alterar { $0.tamanho = nil } }
                    ReguladorFino(valor: item.tamanho ?? tamanhoAuto, faixa: 7...16, passo: 0.5, ativo: item.tamanho != nil) { v in
                        alterar { $0.tamanho = v }
                    }
                    Text(numero(item.tamanho ?? tamanhoAuto) + " pt").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                        .foregroundStyle(item.tamanho == nil ? Color.secondary : Color.primary)
                }
            }
            campo("Peso") {
                LinhaChips(opcoes: [.init(valor: false, titulo: "Normal"), .init(valor: true, titulo: "Negrito")],
                           selecao: item.negrito ?? negritoAuto) { v in alterar { $0.negrito = v } }
                    .frame(width: 170)
                    .padding(3)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(estilo.ladrilho))
            }
            if temCasas {
                campo("Casas") {
                    HStack(spacing: 6) {
                        chip("Global", selecionado: item.casas == nil) { alterar { $0.casas = nil } }
                        ForEach(0...2, id: \.self) { n in
                            chip("\(n)", selecionado: item.casas == n) { alterar { $0.casas = n } }
                        }
                    }
                }
            }
            if temUnidade {
                campo("Unidade") {
                    HStack(spacing: 6) {
                        chip("Mostrar", selecionado: item.unidade != false) { alterar { $0.unidade = nil } }
                        chip("Esconder", selecionado: item.unidade == false) { alterar { $0.unidade = false } }
                    }
                }
            }
            if temSinal {
                campo("Sinal") {
                    HStack(spacing: 6) {
                        chip("Global", selecionado: item.sentido == nil) { alterar { $0.sentido = nil } }
                        ForEach(SentidoRitmo.allCases, id: \.self) { s in
                            chip(s.titulo, selecionado: item.sentido == s) { alterar { $0.sentido = s } }
                        }
                    }
                }
            }
            if temTempo {
                campo("Tempo") {
                    HStack(spacing: 6) {
                        ForEach(FormatoTempo.allCases) { f in
                            chip(f.titulo, selecionado: (item.formatoTempo ?? .relogio) == f) {
                                alterar { $0.formatoTempo = f == .relogio ? nil : f }
                            }
                        }
                    }
                }
            }
            if peca == .icone { campo("Símbolo") { gradeSimbolos } }
            campo("Cor") {
                VStack(alignment: .leading, spacing: 8) {
                    chip("Do estado", selecionado: item.corHex == nil) { alterar { $0.corHex = nil } }
                    HStack(spacing: 5) {
                        ForEach(cores, id: \.self) { hex in
                            let sel = hex.uppercased() == item.corHex?.uppercased()
                            Button { alterar { $0.corHex = hex } } label: {
                                Circle().fill(Color(hex: hex)).frame(width: 20, height: 20)
                                    .overlay(Circle().strokeBorder(sel ? estilo.destaque : Color.primary.opacity(0.25), lineWidth: sel ? 2.5 : 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Cor \(hex)")
                        }
                    }
                    Text("Branco segue a barra (escuro na barra clara)")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            campo("Altura") {
                HStack(spacing: 8) {
                    ReguladorFino(valor: item.deslocamentoY ?? 0, faixa: -3...3, passo: 0.5, ativo: (item.deslocamentoY ?? 0) != 0) { v in
                        alterar { $0.deslocamentoY = v == 0 ? nil : v }
                    }
                    Text(JanelaPreferencias.numeroSinal(item.deslocamentoY ?? 0) + " pt")
                        .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
            }
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    acao("Para a esquerda", "arrow.left", ativo: podeEsquerda, moverEsquerda)
                    acao("Para a direita", "arrow.right", ativo: podeDireita, moverDireita)
                }
                if duasLinhas { acao("Para a outra linha", "arrow.up.arrow.down", ativo: true, outraLinha) }
                acao("Tirar", "trash", ativo: true, vermelho: true, tirar)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    // MARK: Seções

    /// A peça em 2× sobre fundo escuro de barra, com os ajustes de agora.
    private func miniPrevia(_ s: Situacao) -> some View {
        let cor = Color(hex: item.corHex ?? cores.first ?? "#FFFFFF")
        return VistaPeca(peca: item.peca, situacao: s, cor: cor, casas: casasGlobal, sentido: sentidoGlobal,
                         grande: false, linha: duasLinhas ? .cima : nil, escala: 2,
                         tamanho: item.tamanho, negrito: item.negrito, item: item)
            .offset(y: -CGFloat(item.deslocamentoY ?? 0) * 2)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 10)
            .clipped()
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.6)))
            .environment(\.colorScheme, .dark)
    }

    private var textoDoModelo: String { item.texto ?? TextoPeca.textoLivrePadrao }

    private var secaoTextoLivre: some View {
        campo("Texto") {
            VStack(alignment: .leading, spacing: 8) {
                caixa("{pct} · {tempo}", Binding(get: { textoDoModelo },
                                                 set: { v in alterar { $0.texto = String(v.prefix(ItemPeca.limiteTexto)) } }))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(TextoPeca.marcadores, id: \.marcador) { m in
                        Button {
                            alterar { $0.texto = String((textoDoModelo + m.marcador).prefix(ItemPeca.limiteTexto)) }
                        } label: {
                            Text(m.titulo).font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(estilo.ladrilho))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Inserir \(m.marcador)")
                    }
                }
                Text("Toque num marcador para inserir; até \(ItemPeca.limiteTexto) caracteres.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var gradeSimbolos: some View {
        VStack(alignment: .leading, spacing: 8) {
            chip("Desenho do estado", selecionado: item.simbolo == nil) { alterar { $0.simbolo = nil } }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 8), alignment: .leading, spacing: 4) {
                ForEach(ItemPeca.simbolosIcone, id: \.self) { nome in
                    let sel = item.simbolo == nome
                    Button { alterar { $0.simbolo = nome } } label: {
                        Image(systemName: nome).font(.system(size: 13))
                            .foregroundStyle(sel ? estilo.primeiroPlanoSelecionado : Color.primary.opacity(0.8))
                            .frame(width: 28, height: 28)
                            .background(FundoSelecionavel(selecionado: sel, raio: 7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Símbolo \(nome)")
                    .accessibilityAddTraits(sel ? .isSelected : [])
                }
            }
        }
    }

    // MARK: Peças visuais

    private func textoOpcional(_ caminho: WritableKeyPath<ItemPeca, String?>) -> Binding<String> {
        Binding(get: { item[keyPath: caminho] ?? "" },
                set: { v in alterar { $0[keyPath: caminho] = v.isEmpty ? nil : String(v.prefix(ItemPeca.limiteTexto)) } })
    }

    /// Campo de texto; no PNG vira texto estático (o TextField nativo não sai no ImageRenderer).
    @ViewBuilder
    private func caixa(_ dica: String, _ texto: Binding<String>) -> some View {
        Group {
            if paraFoto {
                Text(texto.wrappedValue.isEmpty ? dica : texto.wrappedValue)
                    .font(.system(size: 12))
                    .foregroundStyle(texto.wrappedValue.isEmpty ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(dica, text: texto)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(estilo.ladrilho))
    }

    private func campo<C: View>(_ nome: String, @ViewBuilder _ conteudo: () -> C) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(nome).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
                .padding(.top, 5)
            conteudo().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chip(_ titulo: String, selecionado: Bool, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Text(titulo)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(selecionado ? estilo.primeiroPlanoSelecionado : Color.primary.opacity(0.75))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(FundoSelecionavel(selecionado: selecionado, capsula: true))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selecionado ? .isSelected : [])
    }

    private func acao(_ titulo: String, _ simbolo: String, ativo: Bool, vermelho: Bool = false,
                      _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            HStack(spacing: 6) {
                Image(systemName: simbolo).font(.system(size: 11, weight: .semibold))
                Text(titulo).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(vermelho ? Color(hex: "#FF453A") : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(estilo.ladrilho))
            .opacity(ativo ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!ativo)
        .accessibilityLabel(titulo)
    }
}

// MARK: - Seção "Painel"

/// Ordem e visibilidade das seções do painel da barra de menus (o cabeçalho é fixo).
struct SecaoPainelPrefs: View {
    @Environment(\.estilo) private var estilo
    var ajustes: Ajustes

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Painel").font(.system(size: 20, weight: .bold))
                    Text("Escolha o que aparece ao clicar no item da barra e em que ordem.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button { ajustes.restaurarOrdemPainel() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 11, weight: .semibold))
                        Text("Restaurar ordem").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Restaurar ordem")
            }
            Cartao(padding: 0) {
                VStack(spacing: 0) {
                    let itens = ajustes.secoesPainel
                    ForEach(Array(itens.enumerated()), id: \.element.id) { i, item in
                        if i > 0 { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) }
                        HStack(spacing: 10) {
                            Text(item.secao.titulo)
                                .font(.system(size: 14))
                                .foregroundStyle(item.ligada ? Color.primary : Color.primary.opacity(0.5))
                            Spacer(minLength: 8)
                            passo("chevron.up", "Mover para cima", ativo: i > 0) { ajustes.moverSecao(item.secao, -1) }
                            passo("chevron.down", "Mover para baixo", ativo: i < itens.count - 1) { ajustes.moverSecao(item.secao, 1) }
                            ChaveFina(ligado: item.ligada) { ajustes.alternarSecao(item.secao, ligada: $0) }
                                .accessibilityLabel(item.secao.titulo)
                        }
                        .frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, 14)
            }
        }
    }

    private func passo(_ simbolo: String, _ rotulo: String, ativo: Bool, acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: simbolo).font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(estilo.ladrilho))
                .opacity(ativo ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!ativo)
        .accessibilityLabel(rotulo)
    }
}
