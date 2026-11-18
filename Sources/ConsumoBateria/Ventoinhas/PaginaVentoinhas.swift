import SwiftUI

/// Preferências › Sensores › Ventoinhas (desenho PreferenciasVentoinhas): modo, temperatura que manda, perfis,
/// editor da curva e segurança.
struct PaginaVentoinhas: View {
    @Environment(\.estilo) private var estilo
    @Bindable var controle: ControleVentoinhas
    let leituras: LeiturasModulos
    var paraFoto = false
    var abrirSensores: () -> Void = {}

    @State private var selecionado: UUID?

    private var a: AjustesVentoinhas { controle.ajustes }
    private var fans: [Ventoinha] { leituras.sensores?.ventoinhas ?? [] }

    private var temp: Double? {
        if a.modo != .automatico, let t = controle.temperatura { return t }
        let s = leituras.sensores
        switch a.referencia {
        case .cpu: return s?.cpuC
        case .gpu: return s?.gpuC
        case .maisQuente: return [s?.cpuC, s?.gpuC].compactMap { $0 }.max()
        }
    }

    private var minimoPct: Double? {
        let f = fans.compactMap { v -> Double? in
            guard let mn = v.minimoRpm, let mx = v.maximoRpm, mx > 0 else { return nil }
            return mn / mx * 100
        }
        return f.isEmpty ? nil : f.reduce(0, +) / Double(f.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            cabecalho
            if controle.estado == .precisaAprovar || isIndisponivel || (paraFoto && controle.estado == .naoUsado) {
                AvisoAjudante(estado: controle.estado == .naoUsado ? .precisaAprovar : controle.estado,
                              abrir: controle.abrirItensDeInicio)
            }
            linhaModo
            switch a.modo {
            case .automatico: automatico
            case .manual: manual
            case .curva:
                perfis
                cartaoCurva
            }
            seguranca
        }
        .padding(.horizontal, 30).padding(.vertical, 26)
    }

    private var isIndisponivel: Bool { if case .indisponivel = controle.estado { return true } else { return false } }

    // MARK: Topo

    private var cabecalho: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sensores · Ventoinhas").font(.system(size: 24, weight: .bold))
                Text("Escolha quem decide a rotação: o macOS, um valor fixo ou uma curva pela temperatura.")
                    .font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.65))
            }
            Spacer(minLength: 8)
            Button(action: abrirSensores) {
                Text("Peças da barra e avisos").font(.system(size: 13, weight: .semibold)).foregroundStyle(estilo.destaqueTopo)
            }
            .buttonStyle(.plain)
        }
    }

    private var linhaModo: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                RotuloSecao("Modo")
                SeletorModoVentoinhas(modo: $controle.ajustes.modo, altura: 34)
            }
            .frame(maxWidth: .infinity)
            if a.modo != .manual {
                VStack(alignment: .leading, spacing: 8) {
                    RotuloSecao("Temperatura que manda")
                    HStack(spacing: 6) {
                        ForEach(ReferenciaTemperatura.allCases, id: \.self) { r in
                            chip(r.titulo, a.referencia == r) { controle.ajustes.referencia = r }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if a.modo == .manual {
                VStack(alignment: .leading, spacing: 8) {
                    RotuloSecao("Ventoinhas")
                    HStack(spacing: 6) {
                        chip("As duas juntas", !a.separadas) { controle.ajustes.separadas = false }
                        chip("Cada uma", a.separadas) { controle.ajustes.separadas = true }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Modos

    private var automatico: some View {
        Cartao(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("O macOS decide").font(.system(size: 16, weight: .bold))
                Text("Com o Mac frio as ventoinhas ficam paradas; elas ligam e aceleram conforme esquenta. O My Stats só mostra a rotação, sem mexer em nada.")
                    .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var manual: some View {
        Cartao(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                if a.separadas {
                    ForEach(Array(fans.enumerated()), id: \.offset) { i, v in
                        ControlePorcentagem(titulo: v.nome + rpmDe(v, a.manualPorVentoinha.indices.contains(i) ? a.manualPorVentoinha[i] : a.manualPct),
                                            pct: porVentoinha(i))
                    }
                } else {
                    ControlePorcentagem(titulo: "As duas" + (fans.first.map { rpmDe($0, a.manualPct) } ?? ""), pct: $controle.ajustes.manualPct)
                }
                Text("Abaixo de \(Formato.percentual(minimoPct ?? 25)) a ventoinha gira no mínimo dela; em 0% ela para.")
                    .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.6))
            }
        }
    }

    private func rpmDe(_ v: Ventoinha, _ pct: Double) -> String {
        guard let mx = v.maximoRpm, mx > 0 else { return "" }
        if pct < 0.5 { return " · parada" }
        return " · " + Formato.rpm(max(v.minimoRpm ?? 0, pct / 100 * mx))
    }

    private func porVentoinha(_ i: Int) -> Binding<Double> {
        Binding(get: { i < a.manualPorVentoinha.count ? a.manualPorVentoinha[i] : a.manualPct },
                set: { v in
                    var lista = controle.ajustes.manualPorVentoinha
                    while lista.count <= i { lista.append(controle.ajustes.manualPct) }
                    lista[i] = v
                    controle.ajustes.manualPorVentoinha = lista
                })
    }

    // MARK: Curva

    private var perfis: some View {
        HStack(spacing: 8) {
            RotuloSecao("Perfil").padding(.trailing, 6)
            ForEach(PerfilCurva.allCases, id: \.self) { p in
                chip(p.titulo, a.perfil == p, forte: true) {
                    controle.ajustes.perfil = p
                    selecionado = nil
                }
            }
            Spacer(minLength: 8)
            if a.perfil != .meu {
                Button {
                    controle.ajustes.meuPerfil = a.curva
                    controle.ajustes.perfil = .meu
                } label: {
                    Text("Copiar para Meu perfil").font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14).frame(height: 32)
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.18)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Mexer num perfil pronto cria o Meu perfil a partir dele.
    private func mudarCurva(_ novos: [PontoCurva]) {
        var aj = controle.ajustes
        aj.meuPerfil = novos
        aj.perfil = .meu
        controle.ajustes = aj
    }

    private var cartaoCurva: some View {
        let pct = temp.map { AjustesVentoinhas.pct(curva: a.curva, temp: $0) }
        let pontos = a.perfil == .meu ? a.meuPerfil : a.curva
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Curva · \(a.perfil.titulo)").font(.system(size: 16, weight: .bold))
                Spacer(minLength: 8)
                if let t = temp, let p = pct {
                    (Text("Agora: \(a.referencia == .maisQuente ? "a mais quente" : a.referencia.titulo) está em ")
                     + Text("\(Formato.temperatura(t, curta: false)) → \(Formato.percentual(p))").bold().foregroundColor(estilo.destaqueTopo))
                        .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.7))
                }
            }
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .trailing) {
                    Text("100%"); Spacer(); Text("75%"); Spacer(); Text("50%"); Spacer(); Text("25%"); Spacer(); Text("0%")
                }
                .font(.system(size: 11)).monospacedDigit().foregroundStyle(Color.primary.opacity(0.55))
                .frame(width: 36, height: 300)
                VStack(spacing: 6) {
                    GraficoCurva(pontos: pontos, atual: temp.flatMap { t in pct.map { (t, $0) } }, limite: a.limite,
                                 minimoPct: minimoPct, editavel: true, selecionado: $selecionado, aoMudar: mudarCurva)
                        .frame(height: 300)
                    // Rótulos alinhados às linhas da grade (cada 10 °C).
                    GeometryReader { g in
                        ForEach([30, 40, 50, 60, 70, 80, 90, 100], id: \.self) { t in
                            let x = CGFloat(Double(t) - PontoCurva.tempMin) / CGFloat(PontoCurva.tempMax - PontoCurva.tempMin) * g.size.width
                            Text(t == 30 || t == 100 ? "\(t) °C" : "\(t)")
                                .fixedSize()
                                .frame(width: 60, alignment: t == 30 ? .leading : (t == 100 ? .trailing : .center))
                                .position(x: t == 30 ? x + 30 : (t == 100 ? x - 30 : x), y: 7)
                        }
                    }
                    .frame(height: 14)
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(Color.primary.opacity(0.55))
                }
                listaPontos(pontos)
                    .frame(width: 170)
            }
            Text("Arraste um ponto para mudar; clique no gráfico para criar um ponto; arraste para fora do gráfico para tirar. Em 0% o macOS decide (e para as ventoinhas com o Mac frio); entre 0% e o mínimo, elas giram no mínimo. A faixa laranja é o limite de segurança.")
                .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.62)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(estilo.cartao))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func listaPontos(_ pontos: [PontoCurva]) -> some View {
        let ordenados = pontos.sorted { $0.temp < $1.temp }
        return VStack(alignment: .leading, spacing: 6) {
            RotuloSecao("Pontos")
            ForEach(ordenados) { p in
                let sel = selecionado == p.id
                Button { selecionado = sel ? nil : p.id } label: {
                    HStack {
                        Text("\(Int(p.temp)) °C").monospacedDigit()
                        Spacer()
                        Text(p.pct < 0.5 ? "macOS" : "\(Int(p.pct))%").bold().monospacedDigit()
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(sel ? estilo.destaqueTopo : Color.primary.opacity(0.85))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(sel ? estilo.destaque.opacity(0.16) : Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)
                if sel { ajustePonto(p, pontos) }
            }
            Button { adicionarPonto(pontos) } label: {
                Text("+ Ponto").font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 32)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            .buttonStyle(.plain)
            .disabled(pontos.count >= 12)
        }
    }

    /// Ajuste fino do ponto selecionado: ±1 °C e ±5%, e tirar.
    private func ajustePonto(_ p: PontoCurva, _ pontos: [PontoCurva]) -> some View {
        func mudar(_ f: (inout PontoCurva) -> Void) {
            var novos = pontos
            guard let i = novos.firstIndex(where: { $0.id == p.id }) else { return }
            f(&novos[i])
            novos[i].temp = min(max(novos[i].temp, PontoCurva.tempMin), PontoCurva.tempMax)
            novos[i].pct = min(max(novos[i].pct, 0), 100)
            mudarCurva(novos)
        }
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                passo("minus", "Menos 1 grau") { mudar { $0.temp -= 1 } }
                Text("°C").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                passo("plus", "Mais 1 grau") { mudar { $0.temp += 1 } }
            }
            HStack(spacing: 6) {
                passo("minus", "Menos 5 por cento") { mudar { $0.pct -= 5 } }
                Text("%").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                passo("plus", "Mais 5 por cento") { mudar { $0.pct += 5 } }
            }
            if pontos.count > 2 {
                Button {
                    selecionado = nil
                    mudarCurva(pontos.filter { $0.id != p.id })
                } label: {
                    Text("Tirar ponto").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.quenteModulo)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

    private func passo(_ simbolo: String, _ rotulo: String, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: simbolo).font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(estilo.ladrilho))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rotulo)
    }

    /// Novo ponto no meio do maior intervalo de temperatura.
    private func adicionarPonto(_ pontos: [PontoCurva]) {
        let o = pontos.sorted { $0.temp < $1.temp }
        var novo = PontoCurva(65, AjustesVentoinhas.pct(curva: o, temp: 65))
        if o.count >= 2 {
            let par = zip(o, o.dropFirst()).max { ($0.1.temp - $0.0.temp) < ($1.1.temp - $1.0.temp) }!
            let t = ((par.0.temp + par.1.temp) / 2).rounded()
            novo = PontoCurva(t, AjustesVentoinhas.pct(curva: o, temp: t).rounded())
        }
        selecionado = novo.id
        mudarCurva(o + [novo])
    }

    // MARK: Segurança

    private var seguranca: some View {
        HStack(alignment: .top, spacing: 12) {
            cartaoPequeno("Limite de segurança", "Passou disso, as ventoinhas vão para o máximo, em qualquer modo.") {
                HStack(spacing: 8) {
                    passo("minus", "Diminuir limite") { controle.ajustes.limite = max(AjustesVentoinhas.limiteMin, a.limite - 1) }
                    Text(Formato.temperatura(a.limite, curta: false))
                        .font(.system(size: 14, weight: .bold)).monospacedDigit()
                        .frame(minWidth: 64).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 8).fill(estilo.ladrilho))
                    passo("plus", "Aumentar limite") { controle.ajustes.limite = min(AjustesVentoinhas.limiteMax, a.limite + 1) }
                }
            }
            cartaoPequeno("Se algo der errado", "App fechado, travado, Mac dormindo ou leitura de temperatura parada: em até 8 s o controle volta para o macOS.") {
                Text("Sempre ligado").font(.system(size: 12)).foregroundStyle(Paleta.bom)
            }
            cartaoPequeno("Reaplicar ao abrir", "Quando o Mac reinicia, as ventoinhas voltam para o macOS. Ligado, o My Stats reaplica o seu modo ao abrir.") {
                HStack(spacing: 8) {
                    ChaveFina(ligado: a.reaplicar) { controle.ajustes.reaplicar = $0 }
                    Text(a.reaplicar ? "Ligado" : "Desligado").font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.75))
                }
            }
        }
    }

    private func cartaoPequeno<C: View>(_ titulo: String, _ texto: String, @ViewBuilder _ controle: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titulo).font(.system(size: 14, weight: .bold))
            Text(texto).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            controle()
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.cartao))
    }

    private func chip(_ titulo: String, _ sel: Bool, forte: Bool = false, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Text(titulo)
                .font(.system(size: 13, weight: sel ? .bold : .semibold))
                .foregroundStyle(sel ? (forte ? estilo.primeiroPlanoSelecionado : estilo.destaqueTopo) : Color.primary.opacity(0.8))
                .padding(.horizontal, 12).frame(height: 32)
                .background {
                    if sel && forte { FundoSelecionavel(selecionado: true, capsula: true) }
                    else { Capsule().fill(sel ? estilo.destaque.opacity(0.18) : estilo.ladrilho) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(sel ? .isSelected : [])
    }
}
