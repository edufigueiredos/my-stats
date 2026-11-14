import SwiftUI
import UniformTypeIdentifiers

// Páginas de módulo das Preferências (docs/desenho/modulos/Preferencias.dc.html): "Módulos na barra" (modo, ordem, junto com,
// ligar) e o editor do item de cada módulo. Controles desenhados à mão (ChaveFina, pílulas, FundoSelecionavel), sem Toggle,
// Picker nem Menu nativos, porque o --foto usa ImageRenderer.

// MARK: - Layout em fluxo

/// Chips que quebram de linha quando não cabem.
struct FluxoChipsModulo: Layout {
    var espaco: CGFloat = 6

    private func posicoes(_ largura: CGFloat, _ subviews: Subviews) -> (pontos: [CGPoint], tamanho: CGSize) {
        var pontos: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, alturaLinha: CGFloat = 0, maior: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > 0, x + t.width > largura {
                x = 0
                y += alturaLinha + espaco
                alturaLinha = 0
            }
            pontos.append(CGPoint(x: x, y: y))
            x += t.width + espaco
            alturaLinha = max(alturaLinha, t.height)
            maior = max(maior, x - espaco)
        }
        return (pontos, CGSize(width: maior, height: y + alturaLinha))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let r = posicoes(proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? r.tamanho.width, height: r.tamanho.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = posicoes(bounds.width, subviews)
        for (i, s) in subviews.enumerated() {
            s.place(at: CGPoint(x: bounds.minX + r.pontos[i].x, y: bounds.minY + r.pontos[i].y), proposal: .unspecified)
        }
    }
}

// MARK: - Arrastar

private enum ArrastoEditor: Equatable {
    case paleta(PecaModulo)
    case item(LinhaPeca, Int)
}

private struct SelecaoPecaModulo: Equatable {
    var linha: LinhaPeca
    var id: UUID
}

/// Solta numa linha (no fundo ou sobre uma peça): peça da paleta entra; peça de outra linha muda de linha;
/// peça da mesma linha troca de lugar com a do alvo.
private struct SoltarNaLinhaModulo: DropDelegate {
    let linha: LinhaPeca
    let alvo: Int?
    @Binding var arrastando: ArrastoEditor?
    let adicionar: (PecaModulo, LinhaPeca, Int?) -> Void
    let mover: (LinhaPeca, Int, LinhaPeca, Int?) -> Void

    func dropEntered(info: DropInfo) {
        guard let alvo, case .item(let l, let i)? = arrastando, l == linha, i != alvo else { return }
        mover(l, i, linha, alvo)
        arrastando = .item(linha, alvo)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        defer { arrastando = nil }
        switch arrastando {
        case .paleta(let p)?:
            adicionar(p, linha, alvo)
            return true
        case .item(let l, let i)?:
            if l != linha { mover(l, i, linha, alvo) }
            return true
        case nil:
            return false
        }
    }
}

private struct SoltarModulo: DropDelegate {
    let alvo: Modulo
    @Binding var arrastando: Modulo?
    let mover: (Modulo, Modulo) -> Void

    func dropEntered(info: DropInfo) {
        guard let a = arrastando, a != alvo else { return }
        mover(a, alvo)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        arrastando = nil
        return true
    }
}

/// onDrag e onDrop só fora do --foto: o ImageRenderer desenha um aviso amarelo no lugar de views com onDrop.
private struct PodeArrastarModulo<D: DropDelegate>: ViewModifier {
    let ativo: Bool
    let inicio: () -> NSItemProvider
    let delegado: D

    func body(content: Content) -> some View {
        if ativo {
            content
                .onDrag(inicio)
                .onDrop(of: [UTType.text], delegate: delegado)
        } else {
            content
        }
    }
}

private struct SoltarSoModulo<D: DropDelegate>: ViewModifier {
    let ativo: Bool
    let delegado: D

    func body(content: Content) -> some View {
        if ativo { content.onDrop(of: [UTType.text], delegate: delegado) } else { content }
    }
}

// MARK: - Página

struct PaginaModuloPrefs: View {
    var modulo: Modulo
    var ajustes: Ajustes
    var ajustesModulos: AjustesModulos
    var leituras: LeiturasModulos
    var series: SeriesModulos
    var situacao: Situacao?
    var paraFoto: Bool
    /// Clique numa linha da lista leva para o editor daquele módulo.
    var abrirModulo: (Modulo) -> Void = { _ in }

    @Environment(\.estilo) private var estilo

    @State private var selecao: SelecaoPecaModulo?
    @State private var linhaAlvo: LinhaPeca
    @State private var arrastandoPeca: ArrastoEditor?
    @State private var arrastandoModulo: Modulo?
    @State private var juntoAberto: Modulo?

    static let barraEscuraHex = "#2B1F38"
    static let barraClaraHex = "#ECE7DF"
    static let coresPeca = ["#FFFFFF", "#F2CC7A", "#5BD27A", "#9CC3F5", "#FF8A5C", "#BF5AF2"]

    init(modulo: Modulo, ajustes: Ajustes, ajustesModulos: AjustesModulos, leituras: LeiturasModulos, series: SeriesModulos,
         situacao: Situacao?, paraFoto: Bool, abrirModulo: @escaping (Modulo) -> Void = { _ in },
         pecaSelecionadaInicial: (linha: LinhaPeca, peca: PecaModulo)? = nil) {
        self.modulo = modulo
        self.ajustes = ajustes
        self.ajustesModulos = ajustesModulos
        self.leituras = leituras
        self.series = series
        self.situacao = situacao
        self.paraFoto = paraFoto
        self.abrirModulo = abrirModulo
        let config = ajustesModulos.ajuste(modulo).config
        var inicial: SelecaoPecaModulo?
        if let p = pecaSelecionadaInicial,
           let item = config.pecas(em: p.linha).first(where: { $0.peca == p.peca }) {
            inicial = SelecaoPecaModulo(linha: p.linha, id: item.id)
        }
        _selecao = State(initialValue: inicial)
        _linhaAlvo = State(initialValue: inicial?.linha ?? (config.duasLinhas ? .baixo : .cima))
    }

    private var ajuste: AjusteModulo { ajustesModulos.ajuste(modulo) }
    private var config: ConfigModulo { ajuste.config }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            secaoModulosNaBarra
            secaoEditor
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Comuns

    private func dicaTexto(_ s: String) -> some View {
        Text(s).font(.system(size: 14)).foregroundStyle(.secondary)
    }

    private func rotuloCartao(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.9)
    }

    private func divisorLinha() -> some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
    }

    private func botaoPasso(_ simbolo: String, rotulo: String, ativo: Bool = true, acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: simbolo).font(.system(size: 11, weight: .bold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(estilo.ladrilho))
                .opacity(ativo ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!ativo)
        .accessibilityLabel(rotulo)
    }

    // MARK: Módulos na barra

    private var secaoModulosNaBarra: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Módulos na barra").font(.system(size: 22, weight: .bold))
                    dicaTexto("Arraste para mudar a ordem. \"Junto com\" põe dois ou mais módulos no mesmo item.")
                }
                Spacer(minLength: 8)
                LinhaChips(opcoes: ModoBarraModulos.allCases.map { .init(valor: $0, titulo: $0.titulo) },
                           selecao: ajustesModulos.modoBarra) { ajustesModulos.modoBarra = $0 }
                    .frame(width: 380)
            }
            Cartao(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(ajustesModulos.modulos) { a in
                        linhaModulo(a)
                        divisorLinha()
                    }
                    linhaBateria
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func previaEscura<V: View>(@ViewBuilder _ conteudo: () -> V) -> some View {
        conteudo()
            .padding(.horizontal, 12)
            .frame(minWidth: 150, minHeight: 34)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: Self.barraEscuraHex)))
            .environment(\.colorScheme, .dark)
    }

    private var pegador: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 3) {
                    Circle().frame(width: 2.6, height: 2.6)
                    Circle().frame(width: 2.6, height: 2.6)
                }
            }
        }
        .foregroundStyle(Color.primary.opacity(0.45))
        .frame(width: 14, height: 14)
    }

    private func linhaModulo(_ a: AjusteModulo) -> some View {
        let m = a.modulo
        let junto = textoJunto(a)
        return HStack(spacing: 14) {
            pegador
            Text(m.titulo).font(.system(size: 15, weight: .semibold)).frame(width: 110, alignment: .leading)
            previaEscura {
                VistaItemModulo(modulo: m, config: a.config, leituras: leituras, serie: serieDoItem(m, series: series),
                                corBase: .white, escala: 1.4)
            }
            Text(a.formato.titulo).font(.system(size: 13)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            botaoJunto(m, junto: junto)
            ChaveFina(ligado: a.ligado) { ajustesModulos.alternar(m, ligado: $0) }
                .accessibilityLabel("Mostrar \(m.titulo) na barra")
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { abrirModulo(m) }
        .modifier(PodeArrastarModulo(ativo: !paraFoto, inicio: {
            arrastandoModulo = m
            return NSItemProvider(object: m.rawValue as NSString)
        }, delegado: SoltarModulo(alvo: m, arrastando: $arrastandoModulo, mover: { de, alvo in
            guard let i = ajustesModulos.modulos.firstIndex(where: { $0.modulo == alvo }) else { return }
            ajustesModulos.mover(de, para: i)
        })))
    }

    private func textoJunto(_ a: AjusteModulo) -> String {
        guard let g = a.grupo,
              let outro = ajustesModulos.modulos.first(where: { $0.grupo == g && $0.modulo != a.modulo }) else { return "—" }
        return outro.modulo.titulo
    }

    @ViewBuilder
    private func botaoJunto(_ m: Modulo, junto: String) -> some View {
        let rotulo = Text("Junto com: \(junto)")
            .font(.system(size: 13))
            .foregroundStyle(Color.primary.opacity(0.75))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
        if paraFoto {
            rotulo
        } else {
            Button { juntoAberto = m } label: { rotulo }
                .buttonStyle(.plain)
                .accessibilityLabel("Junto com \(junto)")
                .popover(isPresented: Binding(get: { juntoAberto == m }, set: { if !$0, juntoAberto == m { juntoAberto = nil } }),
                         arrowEdge: .bottom) {
                    listaJunto(m).environment(\.estilo, estilo)
                }
        }
    }

    private func listaJunto(_ m: Modulo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Modulo.allCases.filter { $0 != m }) { outro in
                itemJunto(outro.titulo) {
                    ajustesModulos.juntar(m, com: outro)
                    juntoAberto = nil
                }
            }
            itemJunto("Ninguém") {
                ajustesModulos.juntar(m, com: nil)
                juntoAberto = nil
            }
        }
        .padding(8)
        .frame(width: 170)
    }

    private func itemJunto(_ titulo: String, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Text(titulo).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var linhaBateria: some View {
        let s = situacao ?? .exemplo(.parado)
        return HStack(spacing: 14) {
            Color.clear.frame(width: 14, height: 14)
            Text("Bateria").font(.system(size: 15, weight: .semibold)).frame(width: 110, alignment: .leading)
            previaEscura {
                VistaItemBarra(situacao: s, config: ajustes.config(s.estado), colorir: false, casas: ajustes.casasDecimais,
                               sentido: ajustes.sentido, escala: 1.4, corBase: .white)
            }
            Text(ajustes.formatoBarra.titulo).font(.system(size: 13)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Junto com: —")
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.75))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            ChaveFina(ligado: ajustesModulos.bateriaNaBarra) { ajustesModulos.alternarBateria($0) }
                .accessibilityLabel("Mostrar a bateria na barra")
        }
        .padding(.vertical, 10)
    }

    // MARK: Editor do item

    private var secaoEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("\(modulo.titulo) · editor do item").font(.system(size: 20, weight: .bold))
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    Text("Atualizar a cada").font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.7))
                    LinhaChips(opcoes: IntervaloModulos.allCases.map { .init(valor: $0, titulo: $0.titulo) },
                               selecao: ajustesModulos.intervalo) { ajustesModulos.intervalo = $0 }
                        .frame(width: 170)
                }
            }
            HStack(spacing: 10) {
                previaGrande(claro: false)
                previaGrande(claro: true)
            }
            HStack(spacing: 12) {
                Text("Formato").font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.7))
                LinhaChips(opcoes: FormatoModulo.disponiveis(modulo).map { .init(valor: $0, titulo: $0.titulo) },
                           selecao: ajuste.formato) { ajustesModulos.aplicarFormato($0, em: modulo) }
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    cartaoPaleta
                    cartaoLinha(.cima)
                    cartaoLinha(.baixo)
                    cartaoAoClicar
                    cartaoAvisos
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                cartaoAjuste.frame(width: 300)
            }
        }
    }

    private func previaGrande(claro: Bool) -> some View {
        let corBase = claro ? Color(hex: "#111111") : .white
        return VistaItemModulo(modulo: modulo, config: config, leituras: leituras,
                               serie: serieDoItem(modulo, series: series), corBase: corBase, escala: 2)
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: claro ? Self.barraClaraHex : Self.barraEscuraHex)))
            .overlay {
                if !claro { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.08)) }
            }
    }

    // Paleta

    private var cartaoPaleta: some View {
        Cartao(padding: 0) {
            VStack(alignment: .leading, spacing: 8) {
                rotuloCartao("Peças \(modulo.comArtigo) · arraste para uma linha")
                FluxoChipsModulo {
                    ForEach(PecaModulo.paleta(modulo)) { p in chipPaleta(p) }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }

    private func chipPaleta(_ p: PecaModulo) -> some View {
        let chip = Text(p.titulo(em: modulo))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.85))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.08)))
        return Button { adicionar(p, em: linhaAlvo, indice: nil) } label: { chip }
            .buttonStyle(.plain)
            .accessibilityLabel("Acrescentar \(p.titulo(em: modulo))")
            .modifier(PodeArrastarPaleta(ativo: !paraFoto) {
                arrastandoPeca = .paleta(p)
                return NSItemProvider(object: p.rawValue as NSString)
            })
    }

    // Linhas

    private func nomeLinha(_ l: LinhaPeca) -> String { l == .cima ? "Linha de cima" : "Linha de baixo" }

    private func cartaoLinha(_ linha: LinhaPeca) -> some View {
        let itens = config.pecas(em: linha)
        let alvo = linhaAlvo == linha
        return Cartao(padding: 0) {
            HStack(spacing: 10) {
                Button { linhaAlvo = linha } label: {
                    Text(nomeLinha(linha))
                        .font(.system(size: 13, weight: alvo ? .semibold : .regular))
                        .foregroundStyle(alvo ? Color.primary : Color.primary.opacity(0.7))
                        .frame(width: 120, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(alvo ? .isSelected : [])
                FluxoChipsModulo {
                    ForEach(Array(itens.enumerated()), id: \.element.id) { i, item in chipDaLinha(item, linha, i) }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(alvo ? estilo.destaque.opacity(0.55) : Color.primary.opacity(0.18),
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .modifier(SoltarSoModulo(ativo: !paraFoto, delegado: delegadoDaLinha(linha, alvo: nil)))
                botaoAlinhar(linha)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    private func delegadoDaLinha(_ linha: LinhaPeca, alvo: Int?) -> SoltarNaLinhaModulo {
        SoltarNaLinhaModulo(linha: linha, alvo: alvo, arrastando: $arrastandoPeca,
                            adicionar: { p, l, i in adicionar(p, em: l, indice: i) },
                            mover: { de, i, para, j in moverItem(de: de, indice: i, para: para, indice: j) })
    }

    private func chipDaLinha(_ item: ItemPecaModulo, _ linha: LinhaPeca, _ i: Int) -> some View {
        let sel = selecao == SelecaoPecaModulo(linha: linha, id: item.id)
        let chip = Text(item.peca.titulo(em: modulo))
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(estilo.destaqueTopo)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(estilo.destaque.opacity(0.18)))
            .overlay {
                if sel { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(estilo.destaqueTopo, lineWidth: 1.5) }
            }
        return Button {
            selecao = SelecaoPecaModulo(linha: linha, id: item.id)
            linhaAlvo = linha
        } label: { chip }
            .buttonStyle(.plain)
            .accessibilityLabel("Ajustar \(item.peca.titulo(em: modulo))")
            .accessibilityAddTraits(sel ? .isSelected : [])
            .modifier(PodeArrastarModuloPeca(ativo: !paraFoto, inicio: {
                arrastandoPeca = .item(linha, i)
                return NSItemProvider(object: item.peca.rawValue as NSString)
            }, delegado: delegadoDaLinha(linha, alvo: i)))
    }

    private func botaoAlinhar(_ linha: LinhaPeca) -> some View {
        let atual = config.alinhamento(em: linha)
        return Button {
            let todos = AlinhamentoLinha.allCases
            let proximo = todos[((todos.firstIndex(of: atual) ?? 0) + 1) % todos.count]
            ajustesModulos.atualizarConfig(modulo) { $0.definirAlinhamento(proximo, em: linha) }
        } label: {
            Text(atual.titulo)
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.62))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Alinhamento da \(nomeLinha(linha).lowercased()): \(atual.titulo)")
    }

    // Ao clicar e avisos

    private var cartaoAoClicar: some View {
        Cartao(padding: 0) {
            VStack(alignment: .leading, spacing: 10) {
                rotuloCartao("Ao clicar")
                LinhaChips(opcoes: AoClicarModulo.allCases.map { .init(valor: $0, titulo: $0.titulo(modulo)) },
                           selecao: ajuste.aoClicar) { ajustesModulos.definirAoClicar(modulo, $0) }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }

    private var cartaoAvisos: some View {
        Cartao(padding: 0) {
            VStack(alignment: .leading, spacing: 10) {
                rotuloCartao("Avisos")
                ForEach(ajuste.avisos) { a in
                    HStack(spacing: 12) {
                        Text(a.texto(modulo)).font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading)
                        ChaveFina(ligado: a.ligado) { ligado in
                            var novo = a
                            novo.ligado = ligado
                            ajustesModulos.atualizarAviso(modulo, novo)
                        }
                        .accessibilityLabel(a.texto(modulo))
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }

    // MARK: Mexer nas peças

    private func mudarItem(_ f: (inout ItemPecaModulo) -> Void) {
        guard let s = selecao else { return }
        ajustesModulos.atualizarConfig(modulo) { c in
            c.alterar(s.linha) { lista in
                if let i = lista.firstIndex(where: { $0.id == s.id }) { f(&lista[i]) }
            }
        }
    }

    private func adicionar(_ p: PecaModulo, em linha: LinhaPeca, indice: Int?) {
        var item = ItemPecaModulo(p)
        if p == .texto { item.texto = "{valor}" }
        ajustesModulos.atualizarConfig(modulo) { c in
            c.alterar(linha) { l in
                guard l.count < 12 else { return }
                l.insert(item, at: min(max(indice ?? l.count, 0), l.count))
            }
        }
        linhaAlvo = linha
        selecao = SelecaoPecaModulo(linha: linha, id: item.id)
    }

    private func moverItem(de: LinhaPeca, indice i: Int, para: LinhaPeca, indice j: Int?) {
        ajustesModulos.atualizarConfig(modulo) { c in
            guard c.pecas(em: de).indices.contains(i) else { return }
            if de == para {
                c.alterar(de) { l in
                    let item = l.remove(at: i)
                    l.insert(item, at: min(max(j ?? l.count, 0), l.count))
                }
            } else {
                var item: ItemPecaModulo?
                c.alterar(de) { l in item = l.remove(at: i) }
                guard let item else { return }
                c.alterar(para) { l in l.insert(item, at: min(max(j ?? l.count, 0), l.count)) }
            }
        }
    }

    private func moverSelecionada(_ delta: Int) {
        guard let s = selecao, let i = config.pecas(em: s.linha).firstIndex(where: { $0.id == s.id }) else { return }
        let j = i + delta
        guard config.pecas(em: s.linha).indices.contains(j) else { return }
        ajustesModulos.atualizarConfig(modulo) { c in c.alterar(s.linha) { $0.swapAt(i, j) } }
    }

    private func tirarSelecionada() {
        guard let s = selecao else { return }
        ajustesModulos.atualizarConfig(modulo) { c in c.alterar(s.linha) { $0.removeAll { $0.id == s.id } } }
        selecao = nil
    }

    // MARK: Ajustar peça

    private var itemSelecionado: (item: ItemPecaModulo, indice: Int, linha: LinhaPeca)? {
        guard let s = selecao, let i = config.pecas(em: s.linha).firstIndex(where: { $0.id == s.id }) else { return nil }
        return (config.pecas(em: s.linha)[i], i, s.linha)
    }

    private var cartaoAjuste: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let atual = itemSelecionado {
                ajustarPeca(atual.item, linha: atual.linha, indice: atual.indice)
            } else {
                Text("Clique numa peça para ajustar")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(estilo.cartao))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(paraFoto ? 0.25 : 0.15), radius: 12, y: 6)
    }

    private func tamanhoAuto(_ linha: LinhaPeca) -> Double {
        guard config.duasLinhas else { return 13 }
        return linha == .cima ? 8 : 12
    }

    private func negritoAuto(_ linha: LinhaPeca) -> Bool { !(config.duasLinhas && linha == .cima) }

    private static let pecasNumericas: Set<PecaModulo> = [.valor, .apps, .sistema, .temperatura, .tempGPU, .potencia, .cargaMedia, .texto]
    private static let pecasComTexto: Set<PecaModulo> = [.texto, .rotulo, .separador]

    private var unidadeFaixa: String {
        switch modulo {
        case .rede: return "ms"
        case .sensores: return "°C"
        default: return "%"
        }
    }

    private var passoFaixa: Double {
        switch modulo {
        case .rede: return 10
        default: return 5
        }
    }

    private func numeroCurto(_ v: Double) -> String {
        v.rounded() == v ? "\(Int(v))" : Formato.numero(v, casas: 1)
    }

    private func ajustarPeca(_ item: ItemPecaModulo, linha: LinhaPeca, indice: Int) -> some View {
        let tamanho = item.tamanho ?? tamanhoAuto(linha)
        let negrito = item.negrito ?? negritoAuto(linha)
        let casas = item.casas ?? (item.peca == .cargaMedia ? 1 : 0)
        let faixa = config.faixa
        let limite = config.pecas(em: linha).count - 1
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ajustar peça · \(item.peca.titulo(em: modulo))").font(.system(size: 15, weight: .bold))
                Spacer(minLength: 6)
                Text(linha == .cima ? "linha de cima" : (config.duasLinhas ? "linha de baixo" : "linha única"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            previaDaPeca(item, linha: linha)
            if !paraFoto, Self.pecasComTexto.contains(item.peca) {
                linhaAjuste("Texto") {
                    TextField(item.peca == .texto ? "{valor}" : "Padrão", text: Binding(
                        get: { item.texto ?? "" },
                        set: { novo in mudarItem { $0.texto = novo.isEmpty && $0.peca != .texto ? nil : novo } }))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .frame(width: 150)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(estilo.ladrilho))
                }
            }
            linhaAjuste("Tamanho") {
                botaoPasso("minus", rotulo: "Diminuir tamanho") { mudarItem { $0.tamanho = max(7, tamanho - 1) } }
                valorPilula("\(Int(tamanho)) pt", dica: "Clique para voltar ao tamanho automático") {
                    mudarItem { $0.tamanho = nil }
                }
                botaoPasso("plus", rotulo: "Aumentar tamanho") { mudarItem { $0.tamanho = min(16, tamanho + 1) } }
            }
            linhaAjuste("Peso") {
                pilula("Normal", selecionada: !negrito) { mudarItem { $0.negrito = false } }
                pilula("Negrito", selecionada: negrito) { mudarItem { $0.negrito = true } }
            }
            if Self.pecasNumericas.contains(item.peca) {
                linhaAjuste("Casas decimais") {
                    botaoPasso("minus", rotulo: "Menos casas", ativo: casas > 0) { mudarItem { $0.casas = max(0, casas - 1) } }
                    valorPilula("\(casas)", dica: "") {}
                    botaoPasso("plus", rotulo: "Mais casas", ativo: casas < 2) { mudarItem { $0.casas = min(2, casas + 1) } }
                }
            }
            blocoCor(item)
            linhaAjuste("Faixas") {
                valorPilula("\(numeroCurto(faixa.medio)) · \(numeroCurto(faixa.alto)) \(unidadeFaixa)", dica: "") {}
            }
            linhaAjuste("  Médio") {
                botaoPasso("minus", rotulo: "Diminuir faixa média") { mudarFaixa(medio: -passoFaixa) }
                botaoPasso("plus", rotulo: "Aumentar faixa média") { mudarFaixa(medio: passoFaixa) }
            }
            linhaAjuste("  Alto") {
                botaoPasso("minus", rotulo: "Diminuir faixa alta") { mudarFaixa(alto: -passoFaixa) }
                botaoPasso("plus", rotulo: "Aumentar faixa alta") { mudarFaixa(alto: passoFaixa) }
            }
            linhaAjuste("Altura") {
                let y = item.deslocamentoY ?? 0
                botaoPasso("minus", rotulo: "Descer", ativo: y > -3) { mudarItem { $0.deslocamentoY = max(-3, y - 0.5) } }
                valorPilula("\(numeroCurto(y)) pt", dica: "") {}
                botaoPasso("plus", rotulo: "Subir", ativo: y < 3) { mudarItem { $0.deslocamentoY = min(3, y + 0.5) } }
            }
            HStack(spacing: 8) {
                botaoPasso("arrow.left", rotulo: "Mover para a esquerda", ativo: indice > 0) { moverSelecionada(-1) }
                botaoPasso("arrow.right", rotulo: "Mover para a direita", ativo: indice < limite) { moverSelecionada(1) }
                Text("mover").font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.7))
                Spacer(minLength: 6)
                Button(action: tirarSelecionada) {
                    Text("Tirar").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: "#FFB8A0"))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
    }

    private func mudarFaixa(medio: Double = 0, alto: Double = 0) {
        ajustesModulos.atualizarConfig(modulo) { c in
            var f = c.faixa
            f.medio = max(0, f.medio + medio)
            f.alto = max(f.medio, f.alto + alto)
            c.faixa = f
        }
    }

    private func linhaAjuste<C: View>(_ rotulo: String, @ViewBuilder _ controles: () -> C) -> some View {
        HStack(spacing: 6) {
            Text(rotulo).font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.7))
            Spacer(minLength: 6)
            controles()
        }
    }

    private func valorPilula(_ texto: String, dica: String, acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Text(texto)
                .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                .padding(.horizontal, 10).padding(.vertical, 5)
                .frame(minWidth: 56)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(estilo.ladrilho))
        }
        .buttonStyle(.plain)
        .accessibilityHint(dica)
    }

    private func pilula(_ titulo: String, selecionada: Bool, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Text(titulo)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selecionada ? estilo.primeiroPlanoSelecionado : Color.primary.opacity(0.75))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(FundoSelecionavel(selecionado: selecionada, capsula: true))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selecionada ? .isSelected : [])
    }

    // Cor

    private func blocoCor(_ item: ItemPecaModulo) -> some View {
        let seguirFaixa = item.peca.segueFaixa
        let porFaixa = seguirFaixa && (item.porFaixa ?? config.corPorFaixa)
        let hex = item.corHex?.uppercased()
        let automatica = hex == nil && !porFaixa
        return VStack(alignment: .leading, spacing: 8) {
            Text("Cor").font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.7))
            FluxoChipsModulo {
                pilula("Automática", selecionada: automatica) { mudarItem { $0.corHex = nil; $0.porFaixa = false } }
                if seguirFaixa {
                    pilula("Por faixa", selecionada: porFaixa && hex == nil) { mudarItem { $0.corHex = nil; $0.porFaixa = true } }
                }
                ForEach(Self.coresPeca, id: \.self) { c in
                    Button { mudarItem { $0.corHex = c; $0.porFaixa = false } } label: {
                        Circle().fill(Color(hex: c)).frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(hex == c ? estilo.destaqueTopo : Color.primary.opacity(0.25),
                                                           lineWidth: hex == c ? 2.5 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cor \(c)")
                    .accessibilityAddTraits(hex == c ? .isSelected : [])
                }
            }
        }
    }

    // Prévia grande da peça

    private func configUnica(_ item: ItemPecaModulo) -> ConfigModulo {
        var unica = item
        unica.deslocamentoY = nil
        return ConfigModulo(pecas: [unica], faixa: config.faixa, fonte: config.fonte)
    }

    @ViewBuilder
    private func previaDaPeca(_ item: ItemPecaModulo, linha: LinhaPeca) -> some View {
        let desenhada: Set<PecaModulo> = [.grafico, .icone, .anel, .ponto, .nucleos]
        let nivel = TextoPecaModulo.nivel(modulo, config: config, leituras: leituras)
        let usaFaixa = item.peca.segueFaixa && (item.porFaixa ?? config.corPorFaixa)
        let cor: Color = {
            if let h = item.corHex, !CorDaBarra.ehBranco(h) { return Color(hex: h) }
            if usaFaixa, let h = nivel.corHex { return Color(hex: h) }
            return .white
        }()
        Group {
            if desenhada.contains(item.peca) {
                VistaItemModulo(modulo: modulo, config: configUnica(item), leituras: leituras, serie: serieDoItem(modulo, series: series),
                                corBase: .white, escala: 2)
            } else {
                Text(TextoPecaModulo.texto(item, modulo: modulo, leituras: leituras) ?? Formato.semDado)
                    .font(.system(size: 24, weight: (item.negrito ?? negritoAuto(linha)) ? .bold : .medium,
                                  design: config.fonte.design))
                    .monospacedDigit()
                    .foregroundStyle(cor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: Self.barraEscuraHex)))
    }
}

/// Peça da paleta que se arrasta (só fora do --foto).
private struct PodeArrastarPaleta: ViewModifier {
    let ativo: Bool
    let inicio: () -> NSItemProvider

    func body(content: Content) -> some View {
        if ativo { content.onDrag(inicio) } else { content }
    }
}

/// Peça numa linha: arrasta e também recebe soltar (troca de lugar).
private struct PodeArrastarModuloPeca: ViewModifier {
    let ativo: Bool
    let inicio: () -> NSItemProvider
    let delegado: SoltarNaLinhaModulo

    func body(content: Content) -> some View {
        if ativo {
            content.onDrag(inicio).onDrop(of: [UTType.text], delegate: delegado)
        } else {
            content
        }
    }
}
