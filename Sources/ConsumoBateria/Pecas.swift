import SwiftUI
import AppKit

// MARK: - Ambiente de desenho

private struct DesenhoModeloChave: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Verdadeiro quando a composição vira imagem "template" (só o alfa importa): a pílula
    /// então fura o número em vez de usar texto escuro.
    var desenhoModelo: Bool {
        get { self[DesenhoModeloChave.self] }
        set { self[DesenhoModeloChave.self] = newValue }
    }
}

private struct FonteDoItemChave: EnvironmentKey {
    static let defaultValue = Font.Design.default
}

extension EnvironmentValues {
    /// Família da fonte do item inteiro (padrão, arredondada, mono, serifada).
    var fonteDoItem: Font.Design {
        get { self[FonteDoItemChave.self] }
        set { self[FonteDoItemChave.self] = newValue }
    }
}

// MARK: - Dados derivados da situação

extension Situacao {
    fileprivate var fracaoCarga: Double { min(1, max(0, Double(leitura.percentual) / 100)) }

    fileprivate var ritmoDoItem: Double { ritmoMedio ?? ritmoAgora }

    fileprivate var semRitmo: Bool { estado == .parado || estado == .cheia }
}

// MARK: - Desenhos básicos (viewBox do desenho, escalados)

/// Bateria do desenho: viewBox 30x15, 21,5 de largura útil.
private struct DesenhoBateria: View {
    var fracao: Double
    var cor: Color
    var largura: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 30
            let contorno = Path(roundedRect: CGRect(x: 0.75, y: 0.75, width: 25, height: 13.5), cornerRadius: 3.6)
                .applying(CGAffineTransform(scaleX: s, y: s))
            ctx.stroke(contorno, with: .color(cor.opacity(0.55)), lineWidth: 1.5 * s)
            let ponta = Path(roundedRect: CGRect(x: 27, y: 5, width: 2, height: 5), cornerRadius: 1)
                .applying(CGAffineTransform(scaleX: s, y: s))
            ctx.fill(ponta, with: .color(cor.opacity(0.55)))
            let util = max(2, (21.5 * min(1, max(0, fracao))).rounded())
            let miolo = Path(roundedRect: CGRect(x: 2.75, y: 2.75, width: util, height: 9.5), cornerRadius: 1.8)
                .applying(CGAffineTransform(scaleX: s, y: s))
            ctx.fill(miolo, with: .color(cor))
        }
        .frame(width: largura, height: largura / 2)
    }
}

/// Barra vertical: viewBox 10x20.
private struct DesenhoBarraVertical: View {
    var fracao: Double
    var cor: Color
    var altura: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let s = size.height / 20
            let contorno = Path(roundedRect: CGRect(x: 0.75, y: 0.75, width: 8.5, height: 18.5), cornerRadius: 2.5)
                .applying(CGAffineTransform(scaleX: s, y: s))
            ctx.stroke(contorno, with: .color(cor.opacity(0.55)), lineWidth: 1.5 * s)
            let h = max(2, (15 * min(1, max(0, fracao))).rounded())
            let miolo = Path(roundedRect: CGRect(x: 2.5, y: 2.5 + 15 - h, width: 5, height: h), cornerRadius: 1.2)
                .applying(CGAffineTransform(scaleX: s, y: s))
            ctx.fill(miolo, with: .color(cor))
        }
        .frame(width: altura / 2, height: altura)
    }
}

/// Anel: viewBox 20, raio 7, traço 3, começando no topo.
private struct DesenhoAnel: View {
    var fracao: Double
    var cor: Color
    var lado: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 20
            let centro = CGPoint(x: 10 * s, y: 10 * s)
            var fundo = Path()
            fundo.addEllipse(in: CGRect(x: centro.x - 7 * s, y: centro.y - 7 * s, width: 14 * s, height: 14 * s))
            ctx.stroke(fundo, with: .color(cor.opacity(0.25)), lineWidth: 3 * s)
            let f = min(1, max(0, fracao))
            guard f > 0 else { return }
            var arco = Path()
            let passos = max(2, Int(60 * f))
            for i in 0...passos {
                let a = -Double.pi / 2 + 2 * Double.pi * f * Double(i) / Double(passos)
                let p = CGPoint(x: centro.x + 7 * s * cos(a), y: centro.y + 7 * s * sin(a))
                if i == 0 { arco.move(to: p) } else { arco.addLine(to: p) }
            }
            ctx.stroke(arco, with: .color(cor), style: StrokeStyle(lineWidth: 3 * s, lineCap: .butt))
        }
        .frame(width: lado, height: lado)
    }
}

/// Velocímetro: viewBox 24; ponteiro em π·min(ritmo,30)/30.
private struct DesenhoVelocimetro: View {
    var ritmo: Double
    var cor: Color
    var lado: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 24
            var arco = Path()
            let passos = 40
            for i in 0...passos {
                let a = Double.pi + Double.pi * Double(i) / Double(passos)   // 180° → 360°, passando pelo topo
                let p = CGPoint(x: (12 + 8.5 * cos(a)) * s, y: (18 + 8.5 * sin(a)) * s)
                if i == 0 { arco.move(to: p) } else { arco.addLine(to: p) }
            }
            ctx.stroke(arco, with: .color(cor.opacity(0.55)), style: StrokeStyle(lineWidth: 2 * s, lineCap: .round, lineJoin: .round))
            let t = Double.pi * min(abs(ritmo), 30) / 30
            var ponteiro = Path()
            ponteiro.move(to: CGPoint(x: 12 * s, y: 18 * s))
            ponteiro.addLine(to: CGPoint(x: (12 - 6.5 * cos(t)) * s, y: (18 - 6.5 * sin(t)) * s))
            ctx.stroke(ponteiro, with: .color(cor), style: StrokeStyle(lineWidth: 2.4 * s, lineCap: .round))
            var eixo = Path()
            eixo.addEllipse(in: CGRect(x: 10 * s, y: 16 * s, width: 4 * s, height: 4 * s))
            ctx.fill(eixo, with: .color(cor))
        }
        .frame(width: lado, height: lado)
    }
}

/// Marca do estado: seta (saindo), raio (carregando) ou tomada (na tomada).
private struct DesenhoGlifo: View {
    var estado: EstadoBarra
    var cor: Color
    var altura: CGFloat

    private var proporcao: CGFloat { estado == .parado || estado == .cheia ? 12.0 / 16 : (estado == .carregando ? 10.0 / 14 : 10.0 / 14) }

    var body: some View {
        Canvas { ctx, size in
            switch estado {
            case .carregando:
                let s = size.height / 14
                var p = Path()
                p.move(to: CGPoint(x: 6 * s, y: 0.8 * s))
                p.addLine(to: CGPoint(x: 1.2 * s, y: 7.8 * s))
                p.addLine(to: CGPoint(x: 4.6 * s, y: 7.8 * s))
                p.addLine(to: CGPoint(x: 3.8 * s, y: 13.2 * s))
                p.addLine(to: CGPoint(x: 8.8 * s, y: 6.2 * s))
                p.addLine(to: CGPoint(x: 5.4 * s, y: 6.2 * s))
                p.closeSubpath()
                ctx.fill(p, with: .color(cor))
            case .descarregando, .alto:
                let s = size.height / 14
                var p = Path()
                p.move(to: CGPoint(x: 5 * s, y: 1.5 * s))
                p.addLine(to: CGPoint(x: 5 * s, y: 11.5 * s))
                p.move(to: CGPoint(x: 1.5 * s, y: 8 * s))
                p.addLine(to: CGPoint(x: 5 * s, y: 11.8 * s))
                p.addLine(to: CGPoint(x: 8.5 * s, y: 8 * s))
                ctx.stroke(p, with: .color(cor), style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round, lineJoin: .round))
            case .parado, .cheia:
                let s = size.height / 16
                var p = Path()
                p.move(to: CGPoint(x: 3.5 * s, y: 1 * s)); p.addLine(to: CGPoint(x: 3.5 * s, y: 4.5 * s))
                p.move(to: CGPoint(x: 8.5 * s, y: 1 * s)); p.addLine(to: CGPoint(x: 8.5 * s, y: 4.5 * s))
                p.move(to: CGPoint(x: 2 * s, y: 4.5 * s))
                p.addLine(to: CGPoint(x: 10 * s, y: 4.5 * s))
                p.addLine(to: CGPoint(x: 10 * s, y: 7.5 * s))
                for i in 0...20 {   // meia-volta por baixo, de (10, 7,5) até (2, 7,5)
                    let a = Double.pi * Double(i) / 20
                    p.addLine(to: CGPoint(x: (6 + 4 * cos(a)) * s, y: (7.5 + 4 * sin(a)) * s))
                }
                p.closeSubpath()
                p.move(to: CGPoint(x: 6 * s, y: 11.5 * s)); p.addLine(to: CGPoint(x: 6 * s, y: 15 * s))
                ctx.stroke(p, with: .color(cor), style: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: altura * proporcao, height: altura)
    }
}

// MARK: - Peças na barra

/// Desenha uma das 16 peças na altura da barra de menus (22 pt). `escala` aumenta tudo (miniaturas).
/// `grande` é a variação "empilhada": o valor fica maior para ladear o texto pequeno sobre a bateria.
struct VistaPeca: View {
    var peca: Peca
    var situacao: Situacao
    var cor: Color
    var casas: Int
    var sentido: SentidoRitmo
    var grande = false
    /// Quando o item tem duas linhas: o texto usa o tamanho da linha e os desenhos encolhem para ~11 pt.
    var linha: LinhaPeca? = nil
    var escala: CGFloat = 1
    /// Ajustes do item: tamanho do texto em pt (nil = o da linha) e peso (nil = o da linha).
    var tamanho: Double? = nil
    var negrito: Bool? = nil

    /// Ajustes completos da peça (texto livre, prefixo, formato, símbolo...); nil = automático.
    var item: ItemPeca? = nil

    @Environment(\.desenhoModelo) private var modelo
    @Environment(\.fonteDoItem) private var fonte

    private var tamanhoAuto: CGFloat { VistaPeca.tamanhoAutomatico(linha: linha, grande: grande) }

    /// Quanto o item foi ampliado ou reduzido em relação ao tamanho automático; os desenhos seguem.
    private var razao: CGFloat { tamanho.map { CGFloat($0) / tamanhoAuto } ?? 1 }

    private var tamanhoTexto: CGFloat { (tamanho.map { CGFloat($0) } ?? tamanhoAuto) * escala }

    private var pesoTexto: Font.Weight {
        if let negrito { return negrito ? .bold : .medium }
        switch linha {
        case .cima: return .bold
        case .baixo: return .medium
        case nil: return .semibold
        }
    }

    /// Tamanho automático do texto: 10 pt (cima), 9 pt (baixo), 13 pt (uma linha) ou 16 pt (valor ao lado de texto sobre a bateria).
    nonisolated static func tamanhoAutomatico(linha: LinhaPeca?, grande: Bool) -> CGFloat {
        switch linha {
        case .cima: return 10
        case .baixo: return 9
        case nil: return grande ? 16 : 13
        }
    }

    /// Escala dos desenhos: em duas linhas cada um encolhe para caber em ~11 pt de altura.
    private func e(_ fator: CGFloat) -> CGFloat { (linha == nil ? escala : escala * fator) * razao }

    var body: some View {
        conteudo
            .foregroundStyle(cor)
            .fixedSize()
    }

    @ViewBuilder
    private var conteudo: some View {
        switch peca {
        case .ritmo:
            texto(TextoPeca.moldura(TextoPeca.ritmo(situacao, item: item, casas: casas, sentido: sentido, espaco: linha != nil), item: item))
        case .porcentagem:
            texto(TextoPeca.moldura(TextoPeca.porcentagem(situacao, item: item), item: item))
        case .tempo:
            texto(TextoPeca.moldura(TextoPeca.tempo(situacao, item: item, curto: false), item: item))
        case .horario:
            texto(TextoPeca.moldura(TextoPeca.horario(situacao, item: item), item: item))
        case .texto:
            texto(TextoPeca.moldura(
                TextoPeca.expandir(item?.texto ?? TextoPeca.textoLivrePadrao, situacao, item: item, casas: casas, sentido: sentido),
                item: item))
        case .watts:
            texto(TextoPeca.moldura(TextoPeca.watts(situacao, item: item), item: item))
        case .ritmoWatts:
            duasLinhas(
                topo: situacao.semRitmo
                    ? "Na tomada"
                    : TextoPeca.ritmo(situacao, item: item, casas: casas, sentido: sentido, espaco: true)
                        + " · " + TextoPeca.porcentagem(situacao, item: item),
                baixo: situacao.semRitmo
                    ? (situacao.estado == .cheia ? "cheia em 100%" : "parado em \(Formato.percentual(situacao.leitura.percentual))")
                    : (TextoPeca.watts(situacao, item: item) + " · " + TextoPeca.tempo(situacao, item: item, curto: false)))
        case .etiquetaValor:
            if linha != nil {
                // Dentro de uma linha: "BAT" pequeno ao lado do valor.
                HStack(spacing: 2 * e(1)) {
                    Text(TextoPeca.etiqueta(item: item)).font(.system(size: tamanhoTexto * 0.8, weight: .semibold, design: fonte)).opacity(0.7)
                    Text(TextoPeca.porcentagem(situacao, item: item))
                        .font(.system(size: tamanhoTexto, weight: pesoTexto, design: fonte)).monospacedDigit()
                }
                .lineLimit(1)
            } else {
                VStack(spacing: -1 * e(0.55)) {
                    Text(TextoPeca.etiqueta(item: item)).font(.system(size: 8 * e(0.55), weight: .semibold, design: fonte)).opacity(0.7)
                    Text(TextoPeca.porcentagem(situacao, item: item))
                        .font(.system(size: 12 * e(0.55), weight: negrito == false ? .medium : .bold, design: fonte)).monospacedDigit()
                }
            }
        case .ritmoSobreBateria:
            textoSobreBateria(TextoPeca.moldura(TextoPeca.ritmo(situacao, item: item, casas: casas, sentido: sentido, espaco: false), item: item))
        case .tempoSobreBateria:
            textoSobreBateria(TextoPeca.moldura(TextoPeca.tempo(situacao, item: item, curto: true), item: item))
        case .icone:
            if let simbolo = item?.simbolo {
                Image(systemName: simbolo)
                    .font(.system(size: 12 * e(0.9) * 0.9, weight: .semibold))
            } else {
                DesenhoGlifo(estado: situacao.estado, cor: cor, altura: 12 * e(0.9))
            }
        case .bateria:
            HStack(spacing: 4 * e(0.7)) {
                DesenhoGlifo(estado: situacao.estado, cor: cor, altura: 11 * e(0.7))
                DesenhoBateria(fracao: situacao.fracaoCarga, cor: cor, largura: 24 * e(0.7))
            }
        case .barraVertical:
            DesenhoBarraVertical(fracao: situacao.fracaoCarga, cor: cor, altura: 14 * e(0.78))
        case .anel:
            DesenhoAnel(fracao: situacao.fracaoCarga, cor: cor, lado: 15 * e(0.72))
        case .velocimetro:
            if situacao.estado == .descarregando || situacao.estado == .alto {
                DesenhoVelocimetro(ritmo: situacao.ritmoDoItem, cor: cor, lado: 17 * e(0.64))
            } else {
                // Carregando vira raio; na tomada vira tomada.
                DesenhoGlifo(estado: situacao.estado, cor: cor, altura: 13 * e(0.8))
            }
        case .numeroPilula:
            pilula
        case .espacador:
            Color.clear.frame(width: 6 * escala * razao, height: 1)
        case .separador:
            Text("·")
                .font(.system(size: tamanhoTexto, weight: .bold, design: fonte))
                .opacity(0.7)
        }
    }

    private func texto(_ s: String) -> some View {
        Text(s)
            .font(.system(size: tamanhoTexto, weight: pesoTexto, design: fonte))
            .monospacedDigit()
            .lineLimit(1)
    }

    private func duasLinhas(topo: String, baixo: String) -> some View {
        VStack(alignment: .leading, spacing: -1.5 * escala) {
            Text(topo).font(.system(size: 10 * escala * razao, weight: .bold, design: fonte)).monospacedDigit()
            Text(baixo).font(.system(size: 9 * escala * razao, weight: .medium, design: fonte)).monospacedDigit().opacity(0.85)
        }
        .lineLimit(1)
    }

    /// Texto pequeno sobre a bateria; dentro de uma linha das duas, texto ao lado da bateria pequena.
    @ViewBuilder
    private func textoSobreBateria(_ s: String) -> some View {
        if linha != nil {
            HStack(spacing: 2.5 * e(1)) {
                texto(s)
                DesenhoBateria(fracao: situacao.fracaoCarga, cor: cor, largura: 14 * e(1))
            }
        } else {
            VStack(spacing: 1.3 * e(0.62)) {
                Text(s)
                    .font(.system(size: 8.5 * e(0.62), weight: negrito == false ? .medium : .bold, design: fonte))
                    .monospacedDigit()
                    .lineLimit(1)
                DesenhoBateria(fracao: situacao.fracaoCarga, cor: cor, largura: 18 * e(0.62))
            }
        }
    }

    private var pilula: some View {
        let numero = Text("\(situacao.leitura.percentual)")
            .font(.system(size: 10 * e(0.8), weight: .heavy, design: fonte))
            .monospacedDigit()
        return numero
            .foregroundStyle(modelo ? Color.black : Color(hex: "#17110A"))
            .blendMode(modelo ? .destinationOut : .normal)
            .padding(.horizontal, 4 * e(0.8))
            .padding(.vertical, 1 * e(0.8))
            .background(RoundedRectangle(cornerRadius: 4 * e(0.8), style: .continuous).fill(cor))
            .compositingGroup()
    }
}

// MARK: - Miniatura (paleta e lista do editor)

/// A peça desenhada num quadro mais alto e o título embaixo; é o que a paleta e a lista do editor mostram.
struct MiniaturaPeca: View {
    var peca: Peca
    var situacao: Situacao
    var cor: Color
    var casas: Int
    var sentido: SentidoRitmo
    var mostrarTitulo = true
    var negrito: Bool? = nil
    /// Ajustes da peça (texto, símbolo, formato) para a lista do editor mostrar o que o usuário escolheu.
    var item: ItemPeca? = nil

    private var empilhada: Bool { peca == .ritmoSobreBateria || peca == .tempoSobreBateria }

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if peca == .espacador {
                    HStack(spacing: 6) {
                        Rectangle().fill(.secondary.opacity(0.6)).frame(width: 1, height: 16)
                        Rectangle().fill(.secondary.opacity(0.6)).frame(width: 1, height: 16)
                    }
                } else {
                    VistaPeca(peca: peca, situacao: situacao, cor: cor, casas: casas, sentido: sentido,
                              grande: false, escala: empilhada ? 1.15 : 1.3, negrito: negrito, item: item)
                }
            }
            .frame(minWidth: 30, minHeight: 30)
            if mostrarTitulo {
                Text(peca.titulo)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Altura medida (para caber nos 22 pt)

extension ItemPeca {
    /// Altura de uma linha de texto na fonte real do sistema (tamanho, peso e família), em pt.
    nonisolated static func alturaTexto(tamanho: CGFloat, peso: NSFont.Weight, design: Font.Design) -> CGFloat {
        var fonte = NSFont.systemFont(ofSize: tamanho, weight: peso)
        let nome: NSFontDescriptor.SystemDesign
        switch design {
        case .serif: nome = .serif
        case .rounded: nome = .rounded
        case .monospaced: nome = .monospaced
        default: nome = .default
        }
        if nome != .default, let d = fonte.fontDescriptor.withDesign(nome), let f = NSFont(descriptor: d, size: tamanho) {
            fonte = f
        }
        return ceil(fonte.ascender - fonte.descender + fonte.leading)
    }

    /// Altura do item em pt, na escala 1, dentro da linha dada (nil = uma linha só), medida com a
    /// fonte real nas peças de texto e com os mesmos fatores do desenho nas demais.
    /// Serve para encolher o conjunto proporcionalmente quando a soma passa de 22 pt.
    func alturaNatural(linha: LinhaPeca?, grande: Bool, design: Font.Design = .default) -> CGFloat {
        let auto = VistaPeca.tamanhoAutomatico(linha: linha, grande: grande)
        let t = CGFloat(tamanho ?? Double(auto))
        let r = t / auto
        let duas = linha != nil
        let peso: NSFont.Weight
        if let negrito { peso = negrito ? .bold : .medium } else {
            switch linha {
            case .cima: peso = .bold
            case .baixo: peso = .medium
            case nil: peso = .semibold
            }
        }
        func texto(_ tam: CGFloat, _ p: NSFont.Weight) -> CGFloat { ItemPeca.alturaTexto(tamanho: tam, peso: p, design: design) }
        let extra = CGFloat(abs(deslocamentoY ?? 0))
        let base: CGFloat
        switch peca {
        case .ritmo, .porcentagem, .tempo, .horario, .texto, .watts, .separador:
            base = texto(t, peca == .separador ? .bold : peso)
        case .ritmoWatts:
            base = texto(10 * r, .bold) + texto(9 * r, .medium) - 1.5 * r
        case .etiquetaValor:
            base = duas ? texto(t, peso) : texto(8 * r, .semibold) + texto(12 * r, negrito == false ? .medium : .bold) - 1 * r
        case .ritmoSobreBateria, .tempoSobreBateria:
            base = duas ? texto(t, peso) : texto(8.5 * r, negrito == false ? .medium : .bold) + 1.3 * r + 9 * r
        case .icone: base = (duas ? 10.8 : 12) * r
        case .bateria: base = (duas ? 8.4 : 12) * r
        case .barraVertical: base = (duas ? 10.9 : 14) * r
        case .anel: base = (duas ? 10.8 : 15) * r
        case .velocimetro: base = (duas ? 10.9 : 17) * r
        case .numeroPilula: base = (duas ? 10.8 : 13.5) * r
        case .espacador: return 1
        }
        return base + extra
    }
}
