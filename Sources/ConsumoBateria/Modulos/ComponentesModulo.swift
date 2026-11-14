import SwiftUI

// Peças de tela dos painéis dos módulos (docs/desenho/modulos/). Cores sempre pelo estilo do tema; sem Toggle,
// Picker nem Menu nativos, porque o ImageRenderer do --foto não os desenha.

private let corQuente = Color(hex: "#FF8A5C")
private let corTextoLetra = Color(hex: "#1F1505")

extension Color {
    /// Laranja de "quente" dos desenhos (temperatura e latência altas).
    static var quenteModulo: Color { corQuente }
}

// MARK: - Ações

/// O que os painéis dos módulos pedem ao app. Tudo opcional na prática: o --foto usa `nenhuma`.
struct AcoesModulo {
    var preferencias: () -> Void = {}
    var visaoGeral: () -> Void = {}
    var abrirModulo: (Modulo) -> Void = { _ in }
    var abrirBateria: () -> Void = {}
    var abrirApp: () -> Void = {}
    var ejetar: (URL) -> Void = { _ in }
    var buscarIPPublico: @MainActor () async -> String? = { nil }
    var sair: () -> Void = {}

    static var nenhuma: AcoesModulo { AcoesModulo() }
}

// MARK: - Ícones

/// Ícones dos desenhos (viewBox 24, traço arredondado) na cor do primeiro plano. `modulo` nil = a grade de 4 quadrados.
struct IconeModulo: View {
    let modulo: Modulo?
    let lado: CGFloat
    var espessura: CGFloat = 2

    var body: some View {
        FormaIcone(modulo: modulo)
            .stroke(.foreground, style: StrokeStyle(lineWidth: espessura * lado / 24, lineCap: .round, lineJoin: .round))
            .frame(width: lado, height: lado)
            .accessibilityHidden(true)
    }
}

private struct FormaIcone: Shape {
    let modulo: Modulo?

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch modulo {
        case nil:
            for (x, y) in [(4.0, 4.0), (13, 4), (4, 13), (13, 13)] { p.addRect(CGRect(x: x, y: y, width: 7, height: 7)) }
        case .cpu?:
            p.addRect(CGRect(x: 7, y: 7, width: 10, height: 10))
            for x in [9.5, 14.5] {
                linha(&p, x, 3, x, 7)
                linha(&p, x, 17, x, 21)
            }
            for y in [9.5, 14.5] {
                linha(&p, 3, y, 7, y)
                linha(&p, 17, y, 21, y)
            }
        case .gpu?:
            p.addRect(CGRect(x: 3, y: 7, width: 18, height: 10))
            linha(&p, 7, 17, 7, 20)
            linha(&p, 17, 17, 17, 20)
            p.addEllipse(in: CGRect(x: 4, y: 10, width: 4, height: 4))
            linha(&p, 14, 10, 18, 10)
            linha(&p, 14, 14, 18, 14)
        case .memoria?:
            p.addRect(CGRect(x: 4, y: 8, width: 16, height: 8))
            for x in [8.0, 12, 16] { linha(&p, x, 8, x, 16) }
            linha(&p, 6, 16, 6, 19)
            linha(&p, 18, 16, 18, 19)
        case .disco?:
            p.addRect(CGRect(x: 4, y: 6, width: 16, height: 12))
            linha(&p, 8, 14, 8.01, 14)
            linha(&p, 12, 14, 18, 14)
        case .rede?:
            leque(&p, y: 9, x1: 2.5, x2: 21.5, raio: 14)
            leque(&p, y: 12.5, x1: 5.5, x2: 18.5, raio: 9.5)
            leque(&p, y: 16, x1: 8.5, x2: 15.5, raio: 5)
            linha(&p, 12, 19.5, 12.01, 19.5)
        case .sensores?:
            // Termômetro: haste de topo redondo (raio 2) e bulbo (raio 4), fechando na haste.
            arco(&p, cx: 12, cy: 4, r: 2, de: .pi, ate: 2 * .pi, novo: true)
            let cyBulbo = 13.5 + (16 - 4).squareRoot()
            let a = atan2(13.5 - cyBulbo, 2.0)
            arco(&p, cx: 12, cy: cyBulbo, r: 4, de: a, ate: .pi - a + 0, novo: false)
            p.closeSubpath()
            linha(&p, 12, 9, 12, 17)
        }
        let k = min(rect.width, rect.height) / 24
        return p.applying(CGAffineTransform(scaleX: k, y: k)).offsetBy(dx: rect.minX, dy: rect.minY)
    }

    private func linha(_ p: inout Path, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        p.move(to: CGPoint(x: x1, y: y1))
        p.addLine(to: CGPoint(x: x2, y: y2))
    }

    /// Arco amostrado; ângulos crescentes giram no sentido horário da tela (eixo y para baixo).
    private func arco(_ p: inout Path, cx: Double, cy: Double, r: Double, de: Double, ate: Double, novo: Bool) {
        let passos = 28
        for i in 0...passos {
            let t = de + (ate - de) * Double(i) / Double(passos)
            let ponto = CGPoint(x: cx + r * cos(t), y: cy + r * sin(t))
            if i == 0 && novo { p.move(to: ponto) } else { p.addLine(to: ponto) }
        }
    }

    /// Arco por cima, entre dois pontos na mesma altura (o `a r r 0 0 1` do SVG do Wi-Fi).
    private func leque(_ p: inout Path, y: Double, x1: Double, x2: Double, raio: Double) {
        let cx = (x1 + x2) / 2
        let cy = y + (raio * raio - pow((x2 - x1) / 2, 2)).squareRoot()
        arco(&p, cx: cx, cy: cy, r: raio, de: atan2(y - cy, x1 - cx), ate: atan2(y - cy, x2 - cx), novo: true)
    }
}

// MARK: - Moldura e cabeçalho

private struct AlturaConteudoModulo: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Casca de todo painel de módulo: 400 de largura, conteúdo que rola até o limite da tela e rodapé fixo.
struct MolduraPainelModulo<Conteudo: View, Rodape: View>: View {
    let alturaMaxima: CGFloat?
    let conteudo: Conteudo
    let rodape: Rodape
    @State private var alturaConteudo: CGFloat = 0

    init(alturaMaxima: CGFloat?, @ViewBuilder conteudo: () -> Conteudo, @ViewBuilder rodape: () -> Rodape) {
        self.alturaMaxima = alturaMaxima
        self.conteudo = conteudo()
        self.rodape = rodape()
    }

    var body: some View {
        VStack(spacing: 14) {
            if let limite = alturaMaxima {
                // Altura fixa = conteúdo medido, até o limite da tela; passou disso, rola e o rodapé fica visível.
                let teto = max(limite - 200, 200)
                ScrollView(.vertical, showsIndicators: alturaConteudo > teto) {
                    VStack(spacing: 14) { conteudo }
                        .background(GeometryReader { g in
                            Color.clear.preference(key: AlturaConteudoModulo.self, value: g.size.height)
                        })
                }
                .onPreferenceChange(AlturaConteudoModulo.self) { alturaConteudo = $0 }
                .frame(height: min(alturaConteudo > 0 ? alturaConteudo : teto, teto))
            } else {
                VStack(spacing: 14) { conteudo }
            }
            rodape
        }
        .padding(EdgeInsets(top: 18, leading: 16, bottom: 14, trailing: 16))
        .frame(width: 400)
    }
}

struct CabecalhoModulo: View {
    @Environment(\.estilo) private var estilo
    let icone: Modulo?
    let titulo: String
    let subtitulo: String
    let corPonto: Color
    let rotuloPreferencias: String
    let aoPreferencias: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.degrade)
                IconeModulo(modulo: icone, lado: 26).foregroundStyle(estilo.sobreDestaque)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.system(size: 17, weight: .bold))
                HStack(spacing: 6) {
                    Circle().fill(corPonto).frame(width: 7, height: 7)
                    Text(subtitulo)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.62))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            Button(action: aoPreferencias) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(estilo.ladrilho))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rotuloPreferencias)
        }
    }
}

// MARK: - Períodos e gráficos

struct ChipsPeriodo: View {
    @Environment(\.estilo) private var estilo
    let selecao: PeriodoModulo
    let aoEscolher: (PeriodoModulo) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(PeriodoModulo.allCases) { periodo in
                let ativo = periodo == selecao
                Button { aoEscolher(periodo) } label: {
                    Text(periodo.titulo)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ativo ? estilo.primeiroPlanoSelecionado : Color.primary.opacity(0.66))
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background {
                            if ativo {
                                FundoSelecionavel(selecionado: true, capsula: true)
                            } else {
                                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(estilo.ladrilho)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(ativo ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}

/// Colunas de uma série; `nil` deixa a coluna vazia. Cor e opacidade por coluna (as últimas costumam ficar cheias).
struct GraficoColunas: View {
    let valores: [Double?]
    let maximo: Double
    let altura: CGFloat
    var espaco: CGFloat = 3
    let cor: (Int, Double) -> Color
    let opacidade: (Int) -> Double

    var body: some View {
        HStack(alignment: .bottom, spacing: espaco) {
            ForEach(valores.indices, id: \.self) { i in
                ZStack(alignment: .bottom) {
                    Color.clear
                    if let v = valores[i] {
                        UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 2)
                            .fill(cor(i, v))
                            .opacity(opacidade(i))
                            .frame(height: alturaColuna(v, maximo, altura))
                    }
                }
            }
        }
        .frame(height: altura)
    }
}

private func alturaColuna(_ v: Double, _ maximo: Double, _ altura: CGFloat) -> CGFloat {
    guard maximo > 0, v.isFinite else { return 1 }
    return min(max(CGFloat(v / maximo) * altura, 1), altura)
}

/// Duas séries na mesma coluna, `cima` sobre `baixo` (CPU: sistema embaixo, apps em cima). O máximo vale para a soma.
struct GraficoColunasEmpilhadas: View {
    let baixo: [Double?]
    let cima: [Double?]
    let maximo: Double
    let altura: CGFloat
    let corBaixo: Color
    let corCima: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<max(baixo.count, cima.count), id: \.self) { i in
                let b = i < baixo.count ? baixo[i] : nil
                let c = i < cima.count ? cima[i] : nil
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if let c {
                        UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 2)
                            .fill(corCima)
                            .frame(height: alturaColuna(c, maximo, altura))
                    }
                    if let b {
                        Rectangle().fill(corBaixo).frame(height: alturaColuna(b, maximo, altura))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: altura)
    }
}

/// Leitura/baixa em cima (destaque) e escrita/sobe embaixo (branco 50%), separadas por uma linha.
struct GraficoEspelhado: View {
    @Environment(\.estilo) private var estilo
    let cima: [Double?]
    let baixo: [Double?]
    let maximoCima: Double
    let maximoBaixo: Double
    let alturaCima: CGFloat
    let alturaBaixo: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(cima.indices, id: \.self) { i in
                    ZStack(alignment: .bottom) {
                        Color.clear
                        if let v = cima[i] {
                            UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 2)
                                .fill(estilo.destaque)
                                .opacity(i >= cima.count - 4 ? 1 : 0.65)
                                .frame(height: alturaColuna(v, maximoCima, alturaCima))
                        }
                    }
                }
            }
            .frame(height: alturaCima)
            Rectangle().fill(Color.primary.opacity(0.18)).frame(height: 1)
            HStack(alignment: .top, spacing: 3) {
                ForEach(baixo.indices, id: \.self) { i in
                    ZStack(alignment: .top) {
                        Color.clear
                        if let v = baixo[i] {
                            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 0)
                                .fill(Color.primary.opacity(0.5))
                                .frame(height: alturaColuna(v, maximoBaixo, alturaBaixo))
                        }
                    }
                }
            }
            .frame(height: alturaBaixo)
        }
    }
}

/// Horários espalhados sob um gráfico.
struct EixoTempo: View {
    let rotulos: [String]
    init(_ rotulos: [String]) { self.rotulos = rotulos }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(rotulos.indices, id: \.self) { i in
                Text(rotulos[i])
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary.opacity(0.55))
                if i < rotulos.count - 1 { Spacer(minLength: 4) }
            }
        }
    }
}

// MARK: - Segmentos e anel

/// Barra repartida em partes (memória: apps, fixa, comprimida, cache; potência por componente).
struct BarraSegmentos: View {
    let partes: [(fracao: Double, cor: Color)]
    let altura: CGFloat

    var body: some View {
        GeometryReader { g in
            HStack(spacing: 0) {
                ForEach(partes.indices, id: \.self) { i in
                    Rectangle().fill(partes[i].cor)
                        .frame(width: g.size.width * CGFloat(min(max(partes[i].fracao, 0), 1)))
                }
                Spacer(minLength: 0)
            }
            .frame(width: g.size.width, alignment: .leading)
            .background(Color.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: min(altura / 2, 5), style: .continuous))
        }
        .frame(height: altura)
    }
}

struct LegendaSegmentos: View {
    let itens: [(cor: Color, nome: String, valor: String)]
    let colunas: Int

    var body: some View {
        let n = max(colunas, 1)
        let linhas = stride(from: 0, to: itens.count, by: n).map { Array(itens[$0..<min($0 + n, itens.count)]) }
        VStack(spacing: 8) {
            ForEach(linhas.indices, id: \.self) { l in
                HStack(spacing: 12) {
                    ForEach(0..<n, id: \.self) { c in
                        if c < linhas[l].count {
                            let item = linhas[l][c]
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2).fill(item.cor).frame(width: 9, height: 9)
                                Text(item.nome).font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.7)).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(item.valor).font(.system(size: 13, weight: .semibold)).monospacedDigit().lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                }
            }
        }
    }
}

struct AnelModulo: View {
    let fracao: Double
    let lado: CGFloat
    let espessura: CGFloat
    let cor: Color
    let centro: String?
    let sub: String?

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: espessura)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(fracao, 0), 1)))
                .stroke(cor, style: StrokeStyle(lineWidth: espessura, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if centro != nil || sub != nil {
                VStack(spacing: 0) {
                    if let centro { Text(centro).font(.system(size: lado * 0.28, weight: .bold)).monospacedDigit() }
                    if let sub { Text(sub).font(.system(size: max(lado * 0.14, 9))).foregroundStyle(Color.primary.opacity(0.6)) }
                }
            }
        }
        .padding(espessura / 2)
        .frame(width: lado, height: lado)
    }
}

// MARK: - Linhas e cartões

/// Uma linha de "Quem mais usa": letra colorida, nome, valor e barra fina (recuada 34 para alinhar com o nome).
struct LinhaProcesso: View {
    @Environment(\.estilo) private var estilo
    let indice: Int
    let nome: String
    let valor: String
    let fracao: Double?

    private static let cores = ["#9CC3F5", "#E8A07C", "#A9A6F2", "#D9D4CA"]

    var body: some View {
        HStack(spacing: 10) {
            Text(String(nome.first.map { String($0).uppercased() } ?? "?"))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(corTextoLetra)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: Self.cores[((indice % 4) + 4) % 4])))
            VStack(spacing: 4) {
                HStack {
                    Text(nome).font(.system(size: 14)).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(valor).font(.system(size: 14)).monospacedDigit().foregroundStyle(Color.primary.opacity(0.8)).lineLimit(1)
                }
                if let fracao {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.08))
                            RoundedRectangle(cornerRadius: 2).fill(estilo.destaque)
                                .frame(width: g.size.width * CGFloat(min(max(fracao, 0), 1)))
                        }
                    }
                    .frame(height: 3)
                }
            }
        }
        .padding(.vertical, 7)
    }
}

/// Linhas "rótulo ... valor" dentro de um cartão.
struct CartaoLinhas: View {
    let linhas: [(String, String)]
    init(_ linhas: [(String, String)]) { self.linhas = linhas }

    var body: some View {
        Cartao(padding: 0) {
            VStack(spacing: 0) {
                ForEach(linhas.indices, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(linhas[i].0).font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.62)).fixedSize()
                        Spacer(minLength: 8)
                        Text(linhas[i].1).font(.system(size: 14)).monospacedDigit().multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 7)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
        }
    }
}

/// Ladrilhos lado a lado: rótulo, valor grande e uma linha de apoio.
struct BlocosModulo: View {
    @Environment(\.estilo) private var estilo
    let blocos: [(rotulo: String, valor: String, sub: String)]
    init(_ blocos: [(rotulo: String, valor: String, sub: String)]) { self.blocos = blocos }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(blocos.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 3) {
                    Text(blocos[i].rotulo).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.62)).lineLimit(1)
                    Text(blocos[i].valor)
                        .font(.system(size: 19, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(blocos[i].sub).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.55)).lineLimit(1)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.ladrilho))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(estilo.bordaCartao, lineWidth: 1))
            }
        }
    }
}

struct CabecalhoSecao: View {
    let titulo: String
    let dica: String?
    init(_ titulo: String, dica: String? = nil) {
        self.titulo = titulo
        self.dica = dica
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            RotuloSecao(titulo)
            Spacer(minLength: 8)
            if let dica {
                Text(dica).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.55)).lineLimit(1)
            }
        }
    }
}

// MARK: - Rodapé

struct RodapeModulo: View {
    @Environment(\.estilo) private var estilo
    let tituloBotao: String
    let acaoBotao: () -> Void
    let textoEsquerda: String
    let acaoEsquerda: () -> Void
    let sair: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Button(action: acaoBotao) {
                HStack(spacing: 8) {
                    Text(tituloBotao).font(.system(size: 15, weight: .bold))
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .heavy))
                }
                .foregroundStyle(estilo.primeiroPlanoSelecionado)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(FundoSelecionavel(selecionado: true, raio: 20))
            }
            .buttonStyle(.plain)

            HStack {
                Button(action: acaoEsquerda) {
                    Text(textoEsquerda).font(.system(size: 15)).frame(minHeight: 32)
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: sair) {
                    Text("Sair").font(.system(size: 15)).frame(minHeight: 32)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
            }
            .foregroundStyle(Color.primary.opacity(0.75))
            .padding(.horizontal, 4)
        }
    }
}
