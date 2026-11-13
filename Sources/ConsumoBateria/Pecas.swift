import SwiftUI

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

// MARK: - Dados derivados da situação

extension Situacao {
    fileprivate var fracaoCarga: Double { min(1, max(0, Double(leitura.percentual) / 100)) }

    fileprivate var ritmoDoItem: Double { ritmoMedio ?? ritmoAgora }

    fileprivate var semRitmo: Bool { estado == .parado || estado == .cheia }

    /// Ritmo "−11,3%/h" (sem espaço) ou "−11,3 %/h" (com).
    fileprivate func textoRitmo(casas: Int, sentido: SentidoRitmo, espaco: Bool) -> String {
        Formato.ritmo(ritmoDoItem, casas: casas, sentido: sentido, unidade: false) + (espaco ? " %/h" : "%/h")
    }

    /// Tempo curto: "4:46"; na tomada parada ou cheia, a palavra "tomada".
    fileprivate var textoTempoCurto: String {
        semRitmo ? "tomada" : Formato.duracao(minutos: minutosAteFim)
    }

    /// Tempo da peça Tempo: "4:46", "Parado" ou "Cheia".
    fileprivate var textoTempo: String {
        switch estado {
        case .parado: return "Parado"
        case .cheia: return "Cheia"
        default: return Formato.duracao(minutos: minutosAteFim)
        }
    }

    /// Potência: o que entra (carregando), o que sai (descarregando) ou o que sobra na tomada.
    fileprivate var textoWatts: String {
        switch estado {
        case .carregando:
            return Formato.watts(detalhes.entradaSistemaW ?? leitura.watts, casas: 0)
        case .parado, .cheia:
            return Formato.watts(leitura.watts, casas: 0)
        default:
            return Formato.watts(leitura.watts, casas: 1)
        }
    }

    /// "10,7 W · 4:46".
    fileprivate var textoWattsTempo: String {
        semRitmo ? "" : "\(textoWatts) · \(Formato.duracao(minutos: minutosAteFim))"
    }
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

/// Desenha uma das 15 peças na altura da barra de menus (22 pt). `escala` aumenta tudo (miniaturas).
/// `grande` é a variação "empilhada": o valor fica maior para ladear o texto pequeno sobre a bateria.
struct VistaPeca: View {
    var peca: Peca
    var situacao: Situacao
    var cor: Color
    var casas: Int
    var sentido: SentidoRitmo
    var grande = false
    var escala: CGFloat = 1

    @Environment(\.desenhoModelo) private var modelo

    private var tamanhoTexto: CGFloat { (grande ? 16 : 13) * escala }

    var body: some View {
        conteudo
            .foregroundStyle(cor)
            .fixedSize()
    }

    @ViewBuilder
    private var conteudo: some View {
        switch peca {
        case .ritmo:
            texto(situacao.textoRitmo(casas: casas, sentido: sentido, espaco: false))
        case .porcentagem:
            texto(Formato.percentual(situacao.leitura.percentual))
        case .tempo:
            texto(situacao.textoTempo)
        case .watts:
            texto(situacao.textoWatts)
        case .ritmoWatts:
            duasLinhas(
                topo: situacao.semRitmo ? "Na tomada" : situacao.textoRitmo(casas: casas, sentido: sentido, espaco: true),
                baixo: situacao.semRitmo
                    ? (situacao.estado == .cheia ? "cheia em 100%" : "parado em \(Formato.percentual(situacao.leitura.percentual))")
                    : situacao.textoWattsTempo)
        case .etiquetaValor:
            VStack(spacing: -1 * escala) {
                Text("BAT").font(.system(size: 8 * escala, weight: .semibold)).opacity(0.7)
                Text(Formato.percentual(situacao.leitura.percentual))
                    .font(.system(size: 12 * escala, weight: .bold)).monospacedDigit()
            }
        case .ritmoSobreBateria:
            textoSobreBateria(situacao.textoRitmo(casas: casas, sentido: sentido, espaco: false))
        case .tempoSobreBateria:
            textoSobreBateria(situacao.textoTempoCurto)
        case .icone:
            DesenhoGlifo(estado: situacao.estado, cor: cor, altura: 12 * escala)
        case .bateria:
            HStack(spacing: 4 * escala) {
                DesenhoGlifo(estado: situacao.estado, cor: cor, altura: 11 * escala)
                DesenhoBateria(fracao: situacao.fracaoCarga, cor: cor, largura: 24 * escala)
            }
        case .barraVertical:
            DesenhoBarraVertical(fracao: situacao.fracaoCarga, cor: cor, altura: 14 * escala)
        case .anel:
            DesenhoAnel(fracao: situacao.fracaoCarga, cor: cor, lado: 15 * escala)
        case .velocimetro:
            if situacao.estado == .descarregando || situacao.estado == .alto {
                DesenhoVelocimetro(ritmo: situacao.ritmoDoItem, cor: cor, lado: 17 * escala)
            } else {
                // Carregando vira raio; na tomada vira tomada.
                DesenhoGlifo(estado: situacao.estado, cor: cor, altura: 13 * escala)
            }
        case .numeroPilula:
            pilula
        case .espacador:
            Color.clear.frame(width: 6 * escala, height: 1)
        }
    }

    private func texto(_ s: String) -> some View {
        Text(s)
            .font(.system(size: tamanhoTexto, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
    }

    private func duasLinhas(topo: String, baixo: String) -> some View {
        VStack(alignment: .leading, spacing: -1.5 * escala) {
            Text(topo).font(.system(size: 10 * escala, weight: .bold)).monospacedDigit()
            Text(baixo).font(.system(size: 9 * escala, weight: .medium)).monospacedDigit().opacity(0.85)
        }
        .lineLimit(1)
    }

    private func textoSobreBateria(_ s: String) -> some View {
        VStack(spacing: 1.3 * escala) {
            Text(s)
                .font(.system(size: 8.5 * escala, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
            DesenhoBateria(fracao: situacao.fracaoCarga, cor: cor, largura: 18 * escala)
        }
    }

    private var pilula: some View {
        let numero = Text("\(situacao.leitura.percentual)")
            .font(.system(size: 10 * escala, weight: .heavy))
            .monospacedDigit()
        return numero
            .foregroundStyle(modelo ? Color.black : Color(hex: "#17110A"))
            .blendMode(modelo ? .destinationOut : .normal)
            .padding(.horizontal, 4 * escala)
            .padding(.vertical, 1 * escala)
            .background(RoundedRectangle(cornerRadius: 4 * escala, style: .continuous).fill(cor))
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
                              grande: false, escala: empilhada ? 1.15 : 1.3)
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
