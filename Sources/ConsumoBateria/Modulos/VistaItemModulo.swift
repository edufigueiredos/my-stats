import SwiftUI
import AppKit

// Item de módulo na barra de menus: mesma ideia de VistaItemBarra (22 pt de altura, encolhe quando passa),
// com as peças de PecasModulo.swift. Medidas e cores: docs/desenho/modulos/Main.dc.html.

/// Os 12 últimos valores da métrica principal do módulo (alimenta o minigráfico e a peça Gráfico).
func serieDoItem(_ m: Modulo, series: SeriesModulos) -> [Double] {
    let metrica: MetricaSerie
    switch m {
    case .cpu: metrica = .cpuUso
    case .gpu: metrica = .gpuUso
    case .memoria: metrica = .memUsada
    case .disco: metrica = .discoLeitura
    case .rede: metrica = .redeLatencia
    case .sensores: metrica = .tempCPU
    }
    return series.ultimos(metrica, 12)
}

struct VistaItemModulo: View {
    var modulo: Modulo
    var config: ConfigModulo
    var leituras: LeiturasModulos
    var serie: [Double]
    var corBase: Color = .primary
    /// Desenho para virar imagem "template": tudo em preto, só o alfa importa.
    var modelo = false
    var escala: CGFloat = 1

    static let alturaBarra: CGFloat = 22

    private var nivel: NivelFaixa { TextoPecaModulo.nivel(modulo, config: config, leituras: leituras) }
    private var semRede: Bool { modulo == .rede && TextoPecaModulo.semRede(leituras) }
    private var todos: [ItemPecaModulo] { config.pecas + config.pecasBaixo }

    /// Precisa de cor (não pode ser imagem template): ponto, faixa fora do normal, cor própria ou "sem rede".
    var precisaCor: Bool {
        if todos.contains(where: { $0.peca == .ponto }) { return true }
        if todos.contains(where: { !CorDaBarra.ehBranco($0.corHex) }) { return true }
        if semRede && todos.contains(where: { $0.peca == .latencia || $0.peca == .valor }) { return true }
        if nivel != .normal && todos.contains(where: { usaFaixa($0) }) { return true }
        return false
    }

    private func usaFaixa(_ item: ItemPecaModulo) -> Bool {
        item.peca.segueFaixa && (item.porFaixa ?? config.corPorFaixa)
    }

    // MARK: Tamanhos

    private func tamanhoTexto(_ item: ItemPecaModulo, _ linha: LinhaPeca?) -> CGFloat {
        if let t = item.tamanho { return CGFloat(t) }
        switch linha {
        case .cima?: return 8
        case .baixo?: return 12
        case nil: return 13
        }
    }

    private func alturaNatural(_ item: ItemPecaModulo, _ linha: LinhaPeca?) -> CGFloat {
        switch item.peca {
        case .grafico, .anel, .nucleos: return 12
        case .icone: return 10
        case .ponto: return 6
        default: return tamanhoTexto(item, linha) * 1.2
        }
    }

    private func alturaDaLinha(_ itens: [ItemPecaModulo], _ linha: LinhaPeca?) -> CGFloat {
        itens.map { alturaNatural($0, linha) }.max() ?? 0
    }

    private var ajuste: CGFloat {
        let tg = CGFloat(config.tamanhoGeral)
        let total = (config.duasLinhas
            ? alturaDaLinha(config.pecas, .cima) + alturaDaLinha(config.pecasBaixo, .baixo) + CGFloat(config.espacoLinhas)
            : alturaDaLinha(config.pecas, nil)) * tg
        return total > Self.alturaBarra ? Self.alturaBarra / total : 1
    }

    // MARK: Cores

    private func cor(_ item: ItemPecaModulo) -> Color {
        if modelo { return .black }
        if let hex = item.corHex, !CorDaBarra.ehBranco(hex) { return Color(hex: hex) }
        if usaFaixa(item), let hex = nivel.corHex { return Color(hex: hex) }
        if semRede && (item.peca == .latencia || item.peca == .valor) { return Color(hex: NivelFaixa.semRedeTextoHex) }
        return corBase
    }

    private func peso(_ item: ItemPecaModulo, _ linha: LinhaPeca?) -> Font.Weight {
        if let n = item.negrito { return n ? .bold : .medium }
        if usaFaixa(item) { return nivel.peso }
        return linha == .cima ? .semibold : .bold
    }

    // MARK: Peças

    @ViewBuilder
    private func peca(_ item: ItemPecaModulo, _ linha: LinhaPeca?, _ e: CGFloat) -> some View {
        switch item.peca {
        case .grafico: grafico(item, e)
        case .icone: IconeModulo(modulo: modulo, lado: 10 * e).foregroundStyle(cor(item))
        case .anel: anel(item, e)
        case .ponto: ponto(e)
        case .nucleos: nucleos(item, e)
        default:
            if let t = TextoPecaModulo.texto(item, modulo: modulo, leituras: leituras) {
                Text(t)
                    .font(.system(size: tamanhoTexto(item, linha) * e, weight: peso(item, linha), design: config.fonte.design))
                    .monospacedDigit()
                    .foregroundStyle(cor(item))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    /// 12 colunas em 27×12 com linha de base. Percentuais em escala fixa de 0 a 100; o resto, relativo ao maior.
    private func grafico(_ item: ItemPecaModulo, _ e: CGFloat) -> some View {
        let valores = Array((Array(repeating: 0.0, count: max(12 - serie.count, 0)) + serie).suffix(12))
        let teto: Double
        switch modulo {
        case .cpu, .gpu, .memoria: teto = 100
        default: teto = max(valores.max() ?? 1, 1)
        }
        let altura = 12 * e
        let largura = 27 * e
        let passo = largura / 12
        return HStack(alignment: .bottom, spacing: 0) {
            ForEach(0..<12, id: \.self) { i in
                RoundedRectangle(cornerRadius: 0.4 * e)
                    .frame(width: passo - 0.7 * e, height: max(min(valores[i] / teto, 1) * Double(altura - 1.5 * e), 1 * e))
                    .frame(width: passo, alignment: .leading)
            }
        }
        .foregroundStyle(cor(item))
        .frame(width: largura, height: altura, alignment: .bottom)
        .overlay(alignment: .bottom) {
            Rectangle().fill(cor(item).opacity(0.45)).frame(height: 0.6 * e)
        }
    }

    private func anel(_ item: ItemPecaModulo, _ e: CGFloat) -> some View {
        let c = cor(item)
        return ZStack {
            Circle().stroke(c.opacity(0.28), lineWidth: 1.6 * e)
            Circle().trim(from: 0, to: CGFloat(TextoPecaModulo.fracao(modulo, leituras)))
                .stroke(c, style: StrokeStyle(lineWidth: 1.6 * e, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(0.8 * e)
        .frame(width: 12 * e, height: 12 * e)
    }

    /// Verde abaixo do médio, amarelo entre médio e alto; sem rede ou acima do alto vira anel laranja.
    private func ponto(_ e: CGFloat) -> some View {
        let n = nivel
        return Group {
            if modelo {
                Circle().fill(.black)
            } else if n == .alto {
                Circle().strokeBorder(Color(hex: NivelFaixa.alto.corHex ?? "#FF8A5C"), lineWidth: 1.5 * e)
            } else {
                Circle().fill(Color(hex: n == .medio ? "#F2CC7A" : NivelFaixa.verdeHex))
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 0.6 * e))
            }
        }
        .frame(width: 6 * e, height: 6 * e)
    }

    private func nucleos(_ item: ItemPecaModulo, _ e: CGFloat) -> some View {
        let valores = Array((leituras.cpu?.nucleos ?? []).prefix(16))
        return HStack(alignment: .bottom, spacing: 0.6 * e) {
            ForEach(Array(valores.enumerated()), id: \.offset) { _, v in
                Rectangle().frame(width: 1.4 * e, height: max(min(v / 100, 1) * 12 * e, 1 * e))
            }
        }
        .foregroundStyle(cor(item))
        .frame(height: 12 * e, alignment: .bottom)
    }

    // MARK: Linhas

    private func peca(_ item: ItemPecaModulo, _ linha: LinhaPeca?, esc: CGFloat) -> some View {
        peca(item, linha, esc).offset(y: -CGFloat(item.deslocamentoY ?? 0) * esc)
    }

    private func linhaView(_ itens: [ItemPecaModulo], _ qual: LinhaPeca, _ esc: CGFloat) -> some View {
        HStack(spacing: 3 * esc) {
            ForEach(itens) { item in peca(item, qual, esc: esc) }
        }
        .opacity(qual == .baixo ? 0.9 : 1)
        .frame(maxWidth: .infinity, alignment: config.alinhamento(em: qual).alinhamento)
    }

    var body: some View {
        let esc = escala * ajuste * CGFloat(config.tamanhoGeral)
        Group {
            if config.duasLinhas {
                VStack(alignment: .leading, spacing: CGFloat(config.espacoLinhas) * esc) {
                    linhaView(config.pecas, .cima, esc)
                    linhaView(config.pecasBaixo, .baixo, esc)
                }
            } else {
                HStack(spacing: 4 * esc) {
                    ForEach(config.pecas) { item in peca(item, nil, esc: esc) }
                }
            }
        }
        .fixedSize()
        .frame(height: Self.alturaBarra * escala)
    }
}

// MARK: - Grupo e item único

/// Vários módulos lado a lado num mesmo item (modo Grupos).
struct VistaGrupoModulos: View {
    var itens: [(Modulo, ConfigModulo)]
    var leituras: LeiturasModulos
    var series: SeriesModulos
    var corBase: Color = .primary
    var modelo = false
    var escala: CGFloat = 1

    private func vista(_ m: Modulo, _ c: ConfigModulo) -> VistaItemModulo {
        VistaItemModulo(modulo: m, config: c, leituras: leituras, serie: serieDoItem(m, series: series),
                        corBase: corBase, modelo: modelo, escala: escala)
    }

    var precisaCor: Bool { itens.contains { vista($0.0, $0.1).precisaCor } }

    var body: some View {
        HStack(spacing: 8 * escala) {
            ForEach(Array(itens.enumerated()), id: \.offset) { _, par in vista(par.0, par.1) }
        }
        .frame(height: VistaItemModulo.alturaBarra * escala)
    }
}

/// Modo "Um item só": o valor principal de cada módulo numa linha, "83 · 53 · 50% · 6 ms · 91°".
struct VistaItemUnico: View {
    var modulos: [Modulo]
    var leituras: LeiturasModulos
    var corBase: Color = .primary
    var modelo = false
    var escala: CGFloat = 1

    /// O "%" só aparece no último de uma sequência de percentuais.
    static func texto(_ modulos: [Modulo], _ l: LeiturasModulos) -> String {
        let partes: [(String, Bool)] = modulos.map { m in
            switch m {
            case .cpu, .gpu, .memoria, .disco:
                if let v = TextoPecaModulo.medida(m, l) { return (Formato.numero(v, casas: 0), true) }
                return (Formato.semDado, false)
            default:
                return (TextoPecaModulo.texto(ItemPecaModulo(.valor), modulo: m, leituras: l) ?? Formato.semDado, false)
            }
        }
        var saida: [String] = []
        for (i, p) in partes.enumerated() {
            let proximoPercentual = i + 1 < partes.count && partes[i + 1].1
            saida.append(p.1 && !proximoPercentual ? p.0 + "%" : p.0)
        }
        return saida.joined(separator: " · ")
    }

    var body: some View {
        Text(Self.texto(modulos, leituras))
            .font(.system(size: 13 * escala, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(modelo ? Color.black : corBase)
            .lineLimit(1)
            .fixedSize()
            .frame(height: VistaItemModulo.alturaBarra * escala)
    }
}

// MARK: - Imagem

enum RenderizadorModulos {
    /// Renderiza em escala 2. `colorida` = false vira imagem template (a vista deve ter sido feita com `modelo: true`).
    @MainActor
    static func imagem<V: View>(_ vista: V, colorida: Bool) -> NSImage {
        let r = ImageRenderer(content: vista)
        r.scale = 2
        guard let cg = r.cgImage else {
            return NSImage(systemSymbolName: "gauge", accessibilityDescription: "Módulo") ?? NSImage()
        }
        let imagem = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
        imagem.isTemplate = !colorida
        return imagem
    }
}
