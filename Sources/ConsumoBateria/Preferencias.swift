import SwiftUI
import UniformTypeIdentifiers

/// Janela de Preferências (Preferencias.dc.html). Todos os controles são desenhados, sem Toggle, Picker nem
/// Stepper nativos, para o ImageRenderer gerar o PNG fiel. `paraFoto` tira a ScrollView e fixa a largura.
struct JanelaPreferencias: View {
    var ajustes: Ajustes
    var abrirAoIniciar: Bool
    var alternarAbrirAoIniciar: (Bool) -> Void
    var estadoInicial: EstadoBarra = .descarregando
    var paraFoto = false

    @Environment(\.estilo) private var estilo
    @AppStorage(Ajustes.chaveTema) private var nomeTema = TemaApp.gold.rawValue
    @AppStorage(Ajustes.chaveCorNeon) private var neonHex = "#00F0FF"

    @State private var aberto: EstadoBarra?
    /// Peça em arrasto: o estado da linha de origem e o índice atual dela.
    @State private var arrastando: ArrastoPeca?

    init(ajustes: Ajustes, abrirAoIniciar: Bool, alternarAbrirAoIniciar: @escaping (Bool) -> Void,
         estadoInicial: EstadoBarra = .descarregando, paraFoto: Bool = false) {
        self.ajustes = ajustes
        self.abrirAoIniciar = abrirAoIniciar
        self.alternarAbrirAoIniciar = alternarAbrirAoIniciar
        self.estadoInicial = estadoInicial
        self.paraFoto = paraFoto
        _aberto = State(initialValue: estadoInicial)
    }

    var body: some View {
        Group {
            if paraFoto {
                conteudo.frame(width: 820)
            } else {
                ScrollView { conteudo }.frame(minWidth: 680, idealWidth: 820, minHeight: 520, idealHeight: 760)
            }
        }
    }

    private var conteudo: some View {
        VStack(alignment: .leading, spacing: 26) {
            secaoItem
            secaoRitmo
            secaoTema
            secaoAvisos
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            VStack(alignment: .leading, spacing: 3) {
                titulo("Item da barra de menus")
                dica("Monte o desenho de cada estado. Clique numa peça para tirá-la; arraste para mudar a ordem.")
            }
            RotuloSecao("Formato")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(FormatoBarra.allCases) { formato in ladrilhoFormato(formato) }
            }
            RotuloSecao("Um desenho por estado")
            ForEach(EstadoBarra.allCases) { estado in linhaEstado(estado) }
        }
    }

    private func ladrilhoFormato(_ formato: FormatoBarra) -> some View {
        let selecionado = ajustes.formatoBarra == formato
        let hex = selecionado ? estilo.primeiroPlanoSelecionado.hexString : (estilo.texto?.hexString ?? "#F5F5F5")
        let cfg = ConfigEstado(pecas: formato.pecas(para: .descarregando), corHex: hex)
        return Button { ajustes.aplicar(formato) } label: {
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

    private func linhaEstado(_ estado: EstadoBarra) -> some View {
        let cfg = ajustes.config(estado)
        let cor = Color(hex: cfg.corHex)
        let situacao = Situacao.exemplo(estado)
        let isAberto = aberto == estado
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Circle().fill(cor).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(estado.titulo).font(.system(size: 15, weight: .semibold))
                    Text(estado.dica).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                listaPecas(estado: estado, cfg: cfg, situacao: situacao)
                Button { aberto = isAberto ? nil : estado } label: {
                    Circle().fill(cor).frame(width: 26, height: 26)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cor de \(estado.titulo)")
                Button { aberto = isAberto ? nil : estado } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Adicionar peça em \(estado.titulo)")
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

    private func listaPecas(estado: EstadoBarra, cfg: ConfigEstado, situacao: Situacao) -> some View {
        let cor = Color(hex: cfg.corHex)
        return HStack(spacing: 2) {
            ForEach(Array(cfg.pecas.enumerated()), id: \.offset) { i, peca in
                let miniatura = MiniaturaPeca(peca: peca, situacao: situacao, cor: cor, casas: ajustes.casasDecimais,
                                              sentido: ajustes.sentido, mostrarTitulo: false)
                    .padding(.horizontal, 3)
                    .frame(minHeight: 30)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                if paraFoto {
                    miniatura
                } else {
                    Button { tirar(i, de: estado) } label: { miniatura }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Tirar \(peca.titulo)")
                        .onDrag {
                            arrastando = ArrastoPeca(estado: estado, indice: i)
                            return NSItemProvider(object: peca.rawValue as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: SoltarPeca(
                            estado: estado, alvo: i, arrastando: $arrastando, mover: { de, para in mover(de, para, em: estado) }))
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(minWidth: 60, minHeight: 34, alignment: .trailing)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(estilo.scheme == .light ? 0.06 : 0.28)))
        // Soltar fora de uma peça (no fundo da linha) também encerra o arrasto.
        .onDrop(of: [UTType.text], isTargeted: nil) { _ in
            arrastando = nil
            return false
        }
    }

    private func paleta(estado: EstadoBarra, cfg: ConfigEstado, situacao: Situacao) -> some View {
        let cor = Color(hex: cfg.corHex)
        let amostras = [estado.corPadraoHex, "#34C759", "#E0B357", "#FFFFFF", "#BF5AF2", "#FF9F0A", "#0A84FF", "#FF453A", "#00F0FF"]
        var unicas: [String] = []
        for h in amostras where !unicas.contains(h) { unicas.append(h) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RotuloSecao("Adicionar em \(estado.titulo)")
                Spacer()
                Text("Prévia").font(.system(size: 11)).foregroundStyle(.secondary)
                VistaItemBarra(situacao: situacao, config: cfg, colorir: true, casas: ajustes.casasDecimais,
                               sentido: ajustes.sentido)
                    .padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.55)))
                    .environment(\.colorScheme, .dark)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(Peca.allCases) { peca in
                    Button { acrescentar(peca, em: estado) } label: {
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
        var c = ajustes.config(estado)
        mudar(&c)
        ajustes.configs[estado] = c
    }

    private func tirar(_ indice: Int, de estado: EstadoBarra) {
        atualizar(estado) { if $0.pecas.indices.contains(indice) { $0.pecas.remove(at: indice) } }
    }

    private func acrescentar(_ peca: Peca, em estado: EstadoBarra) {
        atualizar(estado) { $0.pecas.append(peca) }
    }

    private func mover(_ de: Int, _ para: Int, em estado: EstadoBarra) {
        atualizar(estado) {
            guard $0.pecas.indices.contains(de), $0.pecas.indices.contains(para) else { return }
            $0.pecas.move(fromOffsets: [de], toOffset: para > de ? para + 1 : para)
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

    private var secaoAvisos: some View {
        VStack(alignment: .leading, spacing: 12) {
            titulo("Avisos e geral")
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
                    divisor
                    LinhaAlternar(titulo: "Abrir ao iniciar o Mac", ligado: abrirAoIniciar, aoMudar: alternarAbrirAoIniciar)
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
            ChaveDesenhada(ligado: aviso.ligado) { gravar(Aviso(ligado: $0, limite: aviso.limite)) }
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

// MARK: - Chave liga/desliga desenhada

private struct ChaveDesenhada: View {
    @Environment(\.estilo) private var estilo
    let ligado: Bool
    let aoMudar: (Bool) -> Void

    var body: some View {
        Button { aoMudar(!ligado) } label: {
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
        .buttonStyle(.plain)
        .accessibilityAddTraits(ligado ? .isSelected : [])
    }
}

// MARK: - Arrastar para reordenar

private struct ArrastoPeca: Equatable {
    var estado: EstadoBarra
    var indice: Int
}

private struct SoltarPeca: DropDelegate {
    let estado: EstadoBarra
    let alvo: Int
    @Binding var arrastando: ArrastoPeca?
    let mover: (Int, Int) -> Void

    func dropEntered(info: DropInfo) {
        // Solta sobre a linha de outro estado: ignora.
        guard let atual = arrastando, atual.estado == estado, atual.indice != alvo else { return }
        mover(atual.indice, alvo)
        arrastando = ArrastoPeca(estado: estado, indice: alvo)
    }

    func dropExited(info: DropInfo) {}

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        arrastando = nil
        return true
    }
}
