import SwiftUI

// Peças de interface do controle das ventoinhas, usadas no painel Sensores e nas Preferências.

/// Automático | Manual | Curva.
struct SeletorModoVentoinhas: View {
    @Environment(\.estilo) private var estilo
    @Binding var modo: ModoVentoinhas
    var altura: CGFloat = 32

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ModoVentoinhas.allCases, id: \.self) { m in
                let sel = m == modo
                Button { modo = m } label: {
                    Text(m.titulo)
                        .font(.system(size: 13, weight: sel ? .bold : .semibold))
                        .foregroundStyle(sel ? estilo.primeiroPlanoSelecionado : Color.primary.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .frame(height: altura)
                        .background { if sel { FundoSelecionavel(selecionado: true, raio: 9) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(sel ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.cartao))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Modo das ventoinhas")
    }
}

/// Barra de % com atalhos: usada no Manual, para as duas juntas ou uma de cada vez.
struct ControlePorcentagem: View {
    @Environment(\.estilo) private var estilo
    var titulo: String
    @Binding var pct: Double
    var compacto = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(titulo).font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.8))
                Spacer(minLength: 6)
                Text(pct < 0.5 ? "Parada" : Formato.percentual(pct))
                    .font(.system(size: compacto ? 18 : 26, weight: .bold)).monospacedDigit()
                    .foregroundStyle(estilo.destaqueTopo)
            }
            BarraArrastavel(valor: $pct)
                .accessibilityLabel("Rotação: \(titulo)")
            if !compacto {
                HStack(spacing: 6) {
                    atalho("Parada", 0)
                    atalho("50%", 50)
                    atalho("75%", 75)
                    atalho("Máximo", 100)
                }
            }
        }
    }

    private func atalho(_ t: String, _ v: Double) -> some View {
        let sel = abs(pct - v) < 0.5
        return Button { pct = v } label: {
            Text(t).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(sel ? estilo.primeiroPlanoSelecionado : Color.primary.opacity(0.8))
                .padding(.horizontal, 12).frame(height: 28)
                .background(FundoSelecionavel(selecionado: sel, capsula: true))
        }
        .buttonStyle(.plain)
    }
}

/// Gráfico temperatura × % da curva. Editável: arraste um ponto para mudar, clique na área para criar um ponto,
/// arraste um ponto para fora do gráfico para tirar (sempre ficam ao menos dois).
struct GraficoCurva: View {
    @Environment(\.estilo) private var estilo
    var pontos: [PontoCurva]
    /// Temperatura de agora e o % que ela dá.
    var atual: (temp: Double, pct: Double)?
    var limite: Double
    /// % que corresponde ao mínimo da ventoinha (linha tracejada); nil esconde.
    var minimoPct: Double?
    var editavel = false
    var selecionado: Binding<UUID?> = .constant(nil)
    var aoMudar: ([PontoCurva]) -> Void = { _ in }

    @State private var arrastando: UUID?
    @State private var fora = false
    /// Pontos durante o arraste: só este gráfico redesenha; o resto (ajustes, gravação, ventoinhas) recebe ao soltar.
    @State private var rascunho: [PontoCurva]?

    private var mostrados: [PontoCurva] { rascunho ?? pontos }

    private let tMin = PontoCurva.tempMin, tMax = PontoCurva.tempMax

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let x: (Double) -> CGFloat = { CGFloat(($0 - tMin) / (tMax - tMin)) * w }
            let y: (Double) -> CGFloat = { h - CGFloat($0 / 100) * h }
            let ordenados = mostrados.sorted { $0.temp < $1.temp }
            ZStack(alignment: .topLeading) {
                // Grade: 10 °C e 25%.
                Path { p in
                    for t in stride(from: 40.0, to: 100.0, by: 10) { p.move(to: CGPoint(x: x(t), y: 0)); p.addLine(to: CGPoint(x: x(t), y: h)) }
                    for q in stride(from: 25.0, to: 100.0, by: 25) { p.move(to: CGPoint(x: 0, y: y(q))); p.addLine(to: CGPoint(x: w, y: y(q))) }
                }
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)

                // Limite de segurança.
                Rectangle().fill(Color.quenteModulo.opacity(0.14))
                    .frame(width: max(0, w - x(limite)), height: h)
                    .offset(x: x(limite))

                if let m = minimoPct {
                    Path { p in p.move(to: CGPoint(x: 0, y: y(m))); p.addLine(to: CGPoint(x: w, y: y(m))) }
                        .stroke(Color.primary.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                }

                let linha = linhaCurva(ordenados, x: x, y: y, w: w)
                Path { p in
                    p.addPath(linha)
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h))
                    p.closeSubpath()
                }
                .fill(estilo.destaque.opacity(0.14))
                linha.stroke(estilo.destaque, style: StrokeStyle(lineWidth: editavel ? 3 : 2.5, lineJoin: .round))

                if let a = atual {
                    let ax = x(min(max(a.temp, tMin), tMax))
                    Path { p in p.move(to: CGPoint(x: ax, y: 0)); p.addLine(to: CGPoint(x: ax, y: h)) }
                        .stroke(Color.primary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    Circle().fill(Color.white).overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 2))
                        .frame(width: editavel ? 14 : 11, height: editavel ? 14 : 11)
                        .position(x: ax, y: y(a.pct))
                }

                if editavel {
                    ForEach(ordenados) { p in
                        let sel = selecionado.wrappedValue == p.id
                        Circle()
                            .fill(sel ? estilo.destaqueTopo : Color.black.opacity(0.85))
                            .overlay(Circle().strokeBorder(sel ? Color.white.opacity(0.9) : estilo.destaqueTopo, lineWidth: 3))
                            .frame(width: sel ? 18 : 16, height: sel ? 18 : 16)
                            .frame(width: 34, height: 34)          // área de pegar maior que o desenho
                            .contentShape(Circle())
                            .opacity(arrastando == p.id && fora ? 0.35 : 1)
                            .position(x: x(p.temp), y: y(p.pct))
                            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("curva"))
                                .onChanged { v in arrastar(p.id, v.location, w: w, h: h) }
                                .onEnded { v in soltar(p.id, v.location, w: w, h: h) })
                            .accessibilityLabel("Ponto \(Int(p.temp)) graus, \(Int(p.pct)) por cento")
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .named("curva")) { loc in
                guard editavel else { return }
                var novos = pontos
                let n = PontoCurva(valorTemp(loc.x, w: w), valorPct(loc.y, h: h))
                novos.append(n)
                selecionado.wrappedValue = n.id
                aoMudar(novos.sorted { $0.temp < $1.temp })
            }
        }
        .coordinateSpace(name: "curva")
    }

    private func linhaCurva(_ pts: [PontoCurva], x: (Double) -> CGFloat, y: (Double) -> CGFloat, w: CGFloat) -> Path {
        Path { p in
            guard let primeiro = pts.first, let ultimo = pts.last else { return }
            p.move(to: CGPoint(x: 0, y: y(primeiro.pct)))
            for pt in pts { p.addLine(to: CGPoint(x: x(pt.temp), y: y(pt.pct))) }
            p.addLine(to: CGPoint(x: w, y: y(ultimo.pct)))
        }
    }

    private func valorTemp(_ px: CGFloat, w: CGFloat) -> Double {
        (tMin + Double(px / max(w, 1)) * (tMax - tMin)).rounded().clamped(tMin, tMax)
    }

    private func valorPct(_ py: CGFloat, h: CGFloat) -> Double {
        ((1 - Double(py / max(h, 1))) * 100).rounded().clamped(0, 100)
    }

    private func estaFora(_ loc: CGPoint, w: CGFloat, h: CGFloat) -> Bool {
        loc.x < -30 || loc.y < -30 || loc.x > w + 30 || loc.y > h + 30
    }

    private func arrastar(_ id: UUID, _ loc: CGPoint, w: CGFloat, h: CGFloat) {
        if arrastando != id { arrastando = id }
        if selecionado.wrappedValue != id { selecionado.wrappedValue = id }
        var novos = rascunho ?? pontos
        fora = estaFora(loc, w: w, h: h) && novos.count > 2
        guard !fora, let i = novos.firstIndex(where: { $0.id == id }) else { return }
        let t = valorTemp(loc.x, w: w), q = valorPct(loc.y, h: h)
        guard novos[i].temp != t || novos[i].pct != q else { return }
        novos[i].temp = t
        novos[i].pct = q
        rascunho = novos
    }

    private func soltar(_ id: UUID, _ loc: CGPoint, w: CGFloat, h: CGFloat) {
        let base = rascunho ?? pontos
        defer { arrastando = nil; fora = false; rascunho = nil }
        if estaFora(loc, w: w, h: h), base.count > 2 {
            selecionado.wrappedValue = nil
            aoMudar(base.filter { $0.id != id })
        } else if base != pontos {
            aoMudar(base.sorted { $0.temp < $1.temp })
        }
    }
}

private extension Double {
    func clamped(_ a: Double, _ b: Double) -> Double { Swift.min(Swift.max(self, a), b) }
}

/// Aviso de que falta autorizar o ajudante (ou que ele não está disponível).
struct AvisoAjudante: View {
    @Environment(\.estilo) private var estilo
    var estado: EstadoAjudante
    var compacto = false
    var abrir: () -> Void

    var body: some View {
        HStack(alignment: compacto ? .top : .center, spacing: 12) {
            Image(systemName: "lock")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(estilo.sobreDestaque)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(estilo.degrade))
            VStack(alignment: .leading, spacing: 3) {
                Text(titulo).font(.system(size: 14, weight: .bold))
                Text(texto).font(.system(size: compacto ? 12 : 13)).foregroundStyle(Color.primary.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                if compacto, podeAbrir { botao.padding(.top, 4) }
            }
            if !compacto, podeAbrir {
                Spacer(minLength: 8)
                botao
            }
        }
        .padding(compacto ? 12 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.destaque.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(estilo.destaque.opacity(0.35)))
    }

    private var podeAbrir: Bool { if case .indisponivel = estado { return false } else { return true } }

    private var titulo: String {
        if case .indisponivel = estado { return "O controle das ventoinhas não está disponível" }
        return "Falta autorizar o ajudante das ventoinhas"
    }

    private var texto: String {
        if case .indisponivel(let e) = estado { return e }
        return "O macOS só deixa um processo de administrador mudar a rotação. Autorize uma vez em Ajustes do Sistema › Geral › Itens de início, em \"Permitir em segundo plano\". O Automático funciona sem isso."
    }

    private var botao: some View {
        Button(action: abrir) {
            Text("Abrir Itens de início").font(.system(size: 13, weight: .bold))
                .foregroundStyle(estilo.sobreDestaque)
                .padding(.horizontal, 14).frame(height: 32)
                .background(Capsule().fill(estilo.degrade))
        }
        .buttonStyle(.plain)
    }
}

/// Barra de 0 a 100 desenhada à mão (o --foto não desenha o Slider nativo). Marca o mínimo da ventoinha em 25%.
struct BarraArrastavel: View {
    @Environment(\.estilo) private var estilo
    @Binding var valor: Double
    var marca: Double? = 25

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let x = CGFloat(min(max(valor, 0), 100) / 100) * w
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12)).frame(height: 4)
                Capsule().fill(estilo.destaque).frame(width: x, height: 4)
                if let m = marca {
                    Rectangle().fill(Color.primary.opacity(0.35)).frame(width: 2, height: 14)
                        .offset(x: CGFloat(m / 100) * w - 1)
                }
                Circle().fill(Color.white).shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .frame(width: 20, height: 20)
                    .offset(x: x - 10)
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                valor = (Double(v.location.x / max(w, 1)) * 100).rounded().clamped(0, 100)
            })
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityValue("\(Int(valor))%")
        .accessibilityAdjustableAction { d in
            valor = (valor + (d == .increment ? 5 : -5)).clamped(0, 100)
        }
    }
}
