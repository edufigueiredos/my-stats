import SwiftUI
import Charts

// Painel ao clicar na barra de menus. Fiel a docs/desenho/Painel.dc.html e PainelCarregando.dc.html.

/// O que os botões do rodapé fazem; quem hospeda o painel decide.
struct AcoesPainel {
    var maisInformacoes: () -> Void
    var preferencias: () -> Void
    var sair: () -> Void
}

/// Janela do gráfico de ritmo do painel.
enum PeriodoGrafico: String, CaseIterable, Identifiable {
    case quinzeMin, umaHora, seisHoras, vinteQuatroHoras

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .quinzeMin: return "15 min"
        case .umaHora: return "1 h"
        case .seisHoras: return "6 h"
        case .vinteQuatroHoras: return "24 h"
        }
    }

    var minutos: Int {
        switch self {
        case .quinzeMin: return 15
        case .umaHora: return 60
        case .seisHoras: return 360
        case .vinteQuatroHoras: return 1440
        }
    }

    /// Distância entre as marcas do eixo, em minutos (horários redondos).
    var passoMarcas: Int {
        switch self {
        case .quinzeMin: return 5
        case .umaHora: return 15
        case .seisHoras: return 120
        case .vinteQuatroHoras: return 360
        }
    }
}

struct PainelBateria: View {
    @Environment(\.estilo) private var estilo

    let situacao: Situacao?
    let ajustes: Ajustes
    let acoes: AcoesPainel
    /// Altura máxima do painel (ao vivo, a área visível da tela); nil no modo foto, sem rolagem.
    let alturaMaxima: CGFloat?
    @State private var periodo: PeriodoGrafico

    init(situacao: Situacao?, ajustes: Ajustes, acoes: AcoesPainel, periodoInicial: PeriodoGrafico = .umaHora, alturaMaxima: CGFloat? = nil) {
        self.alturaMaxima = alturaMaxima
        self.situacao = situacao
        self.ajustes = ajustes
        self.acoes = acoes
        _periodo = State(initialValue: periodoInicial)
    }

    private var secundario: Color { Color.primary.opacity(0.62) }

    var body: some View {
        VStack(spacing: 14) {
            if let limite = alturaMaxima {
                // Cabe inteiro: sem rolagem. Não cabe: rola o conteúdo e o rodapé fica sempre visível.
                ViewThatFits(in: .vertical) {
                    conteudo
                    ScrollView(.vertical, showsIndicators: false) { conteudo }
                }
                .frame(maxHeight: max(limite - 80, 200))
            } else {
                conteudo
            }
            rodape
        }
        .padding(EdgeInsets(top: 18, leading: 16, bottom: 14, trailing: 16))
        .frame(width: 400)
    }

    private var conteudo: some View {
        VStack(spacing: 14) {
            if let s = situacao {
                cabecalho(s)
                ritmoEAnel(s)
                blocos(s)
                if s.estado == .carregando { paraOndeVai(s) }
                graficoRitmo(s)
                if s.estado == .carregando {
                    if s.detalhes.cargaOtimizada { avisoOtimizado }
                } else {
                    quemMaisGasta(s)
                }
                linhas(s)
            } else {
                Text("Não encontrei a bateria deste Mac.")
                    .font(.system(size: 14))
                    .foregroundStyle(secundario)
                    .frame(maxWidth: .infinity, minHeight: 90)
            }
        }
    }

    // MARK: Cabeçalho

    private func cabecalho(_ s: Situacao) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.degrade)
                if s.estado == .carregando {
                    Image(systemName: "bolt.fill").font(.system(size: 24, weight: .bold))
                } else {
                    Image(systemName: "gauge.with.needle").font(.system(size: 26, weight: .semibold))
                }
            }
            .foregroundStyle(estilo.sobreDestaque)
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(titulo(s)).font(.system(size: 17, weight: .bold))
                HStack(spacing: 6) {
                    Circle().fill(corPonto(s)).frame(width: 7, height: 7)
                    Text(subtitulo(s))
                        .font(.system(size: 13))
                        .foregroundStyle(secundario)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            Button(action: acoes.preferencias) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(estilo.ladrilho))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preferências")
        }
    }

    private func titulo(_ s: Situacao) -> String {
        s.estado == .parado ? "Na tomada" : s.estado.titulo
    }

    private func subtitulo(_ s: Situacao) -> String {
        switch s.estado {
        case .carregando: return s.detalhes.adaptadorNome ?? "Na tomada"
        case .cheia: return "Na tomada · bateria cheia"
        case .parado: return "Na tomada · não está carregando"
        case .alto: return "Na bateria · consumo alto" + (s.detalhes.poucaEnergia ? " · Pouca Energia" : "")
        case .descarregando: return "Na bateria" + (s.detalhes.poucaEnergia ? " · Pouca Energia ligado" : "")
        }
    }

    private func corPonto(_ s: Situacao) -> Color {
        switch s.estado {
        case .carregando, .cheia: return Paleta.bom
        case .parado: return Color(hex: "#BF5AF2")
        case .alto: return Paleta.alto
        case .descarregando: return Color(hex: "#FFB340")
        }
    }

    // MARK: Ritmo e anel

    private func ritmoEAnel(_ s: Situacao) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rotuloRitmo(s))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.primary.opacity(0.6))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Formato.ritmo(s.ritmoMedio, casas: ajustes.casasDecimais, sentido: .sinais, unidade: false))
                        .font(.system(size: 46, weight: .bold))
                        .tracking(-1.4)
                        .foregroundStyle(estilo.destaqueTopo)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("%/h")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.75))
                }
                Text(linhaAgora(s))
                    .font(.system(size: 13))
                    .foregroundStyle(secundario)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)

            anel(s)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(estilo.cartao))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(estilo.bordaCartao, lineWidth: 1))
    }

    private func rotuloRitmo(_ s: Situacao) -> String {
        let base: String
        switch s.estado {
        case .carregando: base = "Carregando"
        case .cheia, .parado: base = "Na tomada"
        default: base = "Gastando"
        }
        let media = ajustes.mediaRitmo == .agora ? "agora" : "média de \(ajustes.mediaRitmo.titulo)"
        return "\(base) · \(media)"
    }

    private func linhaAgora(_ s: Situacao) -> String {
        let agora = "Agora " + Formato.ritmo(s.ritmoAgora, casas: ajustes.casasDecimais, sentido: .sinais)
        if s.estado == .carregando { return agora + " · desacelera perto de 80%" }
        guard let hora = s.ritmoUltimaHora else { return agora }
        return agora + " · última hora " + Formato.ritmo(hora, casas: ajustes.casasDecimais, sentido: .sinais)
    }

    private func anel(_ s: Situacao) -> some View {
        let fracao = min(max(Double(s.leitura.percentual) / 100, 0), 1)
        return ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: 8)
            Circle().trim(from: 0, to: fracao)
                .stroke(estilo.destaque, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(Formato.percentual(s.leitura.percentual))
                    .font(.system(size: 22, weight: .bold))
                if let t = textoAnel(s) {
                    Text(t).font(.system(size: 12)).foregroundStyle(secundario)
                }
            }
            .monospacedDigit()
        }
        .padding(4)
        .frame(width: 96, height: 96)
    }

    private func textoAnel(_ s: Situacao) -> String? {
        guard let m = s.minutosAteFim, m.isFinite, m >= 0 else { return nil }
        let d = Formato.duracao(minutos: m)
        return s.estado == .carregando ? "cheia \(d)" : d
    }

    // MARK: Blocos

    private func blocos(_ s: Situacao) -> some View {
        let carregando = s.estado == .carregando
        return HStack(alignment: .top, spacing: 8) {
            if s.leitura.naTomada {
                let entrada = s.detalhes.entradaSistemaW ?? abs(s.leitura.watts)
                bloco(icone: AnyView(setaW(para: .cima)), rotulo: "Entrando",
                      valor: Formato.watts(entrada, casas: carregando ? 0 : 1),
                      sub: s.detalhes.adaptadorW.map { "de \(Int($0.rounded())) W" })
            } else {
                bloco(icone: AnyView(setaW(para: .baixo)), rotulo: "Saindo",
                      valor: Formato.watts(s.leitura.watts), sub: nil, barra: min(abs(s.leitura.watts) / 30, 1))
            }
            if carregando {
                bloco(icone: AnyView(relogio), rotulo: "Cheia em", valor: horasMinutos(s.minutosAteFim),
                      sub: s.horarioFim.map { "às " + Formato.horario($0) })
                bloco(icone: AnyView(relogio), rotulo: "Até 80%", valor: minutosCurtos(s.minutosAte80),
                      sub: s.horarioAte80.map { "às " + Formato.horario($0) })
            } else {
                bloco(icone: AnyView(relogio), rotulo: "Acaba em", valor: horasMinutos(s.minutosAteFim),
                      sub: s.horarioFim.map { "às " + Formato.horario($0) })
                bloco(icone: AnyView(iconeBateria), rotulo: "Bateria", valor: Formato.percentual(s.leitura.percentual),
                      sub: nil, barra: Double(s.leitura.percentual) / 100)
            }
        }
    }

    private enum Direcao { case cima, baixo }

    private func setaW(para direcao: Direcao) -> some View {
        Image(systemName: direcao == .cima ? "arrow.up" : "arrow.down")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(direcao == .cima ? Paleta.bom : Color(hex: "#FFB340"))
    }

    private var relogio: some View {
        Image(systemName: "clock").font(.system(size: 11, weight: .medium))
    }

    private var iconeBateria: some View {
        Image(systemName: "battery.50percent").font(.system(size: 11, weight: .medium))
    }

    private func bloco(icone: AnyView, rotulo: String, valor: String, sub: String?, barra: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                icone
                Text(rotulo).font(.system(size: 12))
            }
            .foregroundStyle(secundario)
            Text(valor)
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let barra {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.10))
                        RoundedRectangle(cornerRadius: 2).fill(estilo.destaque)
                            .frame(width: g.size.width * min(max(barra, 0), 1))
                    }
                }
                .frame(height: 4)
            } else if let sub {
                Text(sub).font(.system(size: 12)).foregroundStyle(secundario)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.cartao))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(estilo.bordaCartao, lineWidth: 1))
    }

    /// "4h46", "1h12".
    private func horasMinutos(_ minutos: Double?) -> String {
        guard let minutos, minutos.isFinite, minutos >= 0 else { return "–" }
        let m = Int(minutos.rounded())
        return String(format: "%dh%02d", m / 60, m % 60)
    }

    /// "41 min" abaixo de uma hora; senão "1h05".
    private func minutosCurtos(_ minutos: Double?) -> String {
        guard let minutos, minutos.isFinite, minutos >= 0 else { return "–" }
        return minutos < 60 ? "\(Int(minutos.rounded())) min" : horasMinutos(minutos)
    }

    // MARK: Para onde vai o que entra

    @ViewBuilder
    private func paraOndeVai(_ s: Situacao) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            RotuloSecao("Para onde vai o que entra")
            Cartao(padding: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    if let bat = s.paraBateriaW {
                        if let mac = s.paraMacW {
                            let total = max(bat + mac, 0.1)
                            GeometryReader { g in
                                HStack(spacing: 2) {
                                    RoundedRectangle(cornerRadius: 2).fill(estilo.destaque)
                                        .frame(width: max((g.size.width - 2) * bat / total, 0))
                                    RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.35))
                                }
                            }
                            .frame(height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            HStack {
                                legenda(estilo.destaque, "Bateria \(Formato.watts(bat, casas: 0))")
                                Spacer()
                                legenda(Color.primary.opacity(0.35), "Mac \(Formato.watts(mac, casas: 0))")
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(estilo.destaque).frame(height: 14)
                            legenda(estilo.destaque, "Bateria \(Formato.watts(bat, casas: 0))")
                        }
                    } else {
                        Text("Sem leitura da potência que entra.")
                            .font(.system(size: 14))
                            .foregroundStyle(secundario)
                    }
                }
                .monospacedDigit()
            }
        }
    }

    private func legenda(_ cor: Color, _ texto: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(cor).frame(width: 8, height: 8)
            Text(texto).font(.system(size: 14))
        }
    }

    // MARK: Gráfico do ritmo

    private func graficoRitmo(_ s: Situacao) -> some View {
        let barras = BarraRitmo.agrupar(s.serie, fim: s.serie.last?.data ?? s.leitura.data, minutos: periodo.minutos)
        let carregando = s.estado == .carregando
        let teto = max(carregando ? 45 : 18, (barras.map { abs($0.valor) }.max() ?? 0) * 1.1)
        let fim = s.serie.last?.data ?? s.leitura.data
        let inicio = fim.addingTimeInterval(-Double(periodo.minutos) * 60)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                RotuloSecao("Ritmo")
                Spacer()
                HStack(spacing: 4) {
                    ForEach(PeriodoGrafico.allCases) { p in
                        Button { periodo = p } label: {
                            Text(p.titulo)
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 9)
                                .frame(height: 24)
                                .foregroundStyle(p == periodo ? estilo.primeiroPlanoSelecionado : Color.primary.opacity(0.75))
                                .background(FundoSelecionavel(selecionado: p == periodo, capsula: true))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(p == periodo ? .isSelected : [])
                    }
                }
            }
            Cartao(padding: 12) {
                GraficoBarras(barras: barras, carregando: carregando, teto: teto,
                              media: carregando ? nil : s.ritmoMedio, inicio: inicio, fim: fim,
                              marcas: marcas(inicio: inicio, fim: fim))
            }
        }
    }

    /// Horários redondos dentro da janela, sem marca colada na borda direita (o rótulo seria cortado).
    private func marcas(inicio: Date, fim: Date) -> [Date] {
        let passo = TimeInterval(periodo.passoMarcas * 60)
        let cal = Calendar.current
        let diaInicio = cal.startOfDay(for: inicio)
        let limite = fim.addingTimeInterval(-Double(periodo.minutos) * 60 * 0.1)
        var d = diaInicio
        var resultado: [Date] = []
        while d <= limite {
            if d >= inicio { resultado.append(d) }
            d = d.addingTimeInterval(passo)
        }
        return resultado
    }

    // MARK: Quem mais gasta

    private func quemMaisGasta(_ s: Situacao) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                RotuloSecao("Quem mais gasta")
                Spacer()
                Text("estimado").font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.55))
            }
            Cartao(padding: 12) {
                if s.apps.isEmpty {
                    Text("Medindo…")
                        .font(.system(size: 14))
                        .foregroundStyle(secundario)
                        .padding(.vertical, 7)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(appsVisiveis(s.apps).enumerated()), id: \.element.id) { i, app in
                            linhaApp(app, indice: i)
                        }
                    }
                    .padding(.vertical, -1)
                }
            }
        }
    }

    /// Os 3 primeiros apps mais o item de sistema no fim, se existir (o desenho mostra 3 apps + sistema).
    private func appsVisiveis(_ apps: [ConsumoApp]) -> [ConsumoApp] {
        let sistema = apps.last { $0.id == "sistema" }
        let normais = apps.filter { $0.id != "sistema" }
        return Array(normais.prefix(3)) + (sistema.map { [$0] } ?? [])
    }

    private static let cores = ["#E8A07C", "#9CC3F5", "#A9A6F2", "#D9D4CA"]

    private func linhaApp(_ app: ConsumoApp, indice: Int) -> some View {
        HStack(spacing: 10) {
            Text(String(app.nome.first.map { String($0).uppercased() } ?? "?"))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: "#1F1505"))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: Self.cores[indice % Self.cores.count])))
            VStack(spacing: 4) {
                HStack {
                    Text(app.nome).font(.system(size: 14)).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Formato.watts(app.watts))
                        .font(.system(size: 14)).monospacedDigit()
                        .foregroundStyle(Color.primary.opacity(0.75))
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.08))
                        RoundedRectangle(cornerRadius: 2).fill(estilo.destaque)
                            .frame(width: g.size.width * min(max(app.fracao, 0), 1))
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.vertical, 7)
    }

    // MARK: Aviso, linhas e rodapé

    private var avisoOtimizado: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(estilo.sobreDestaque)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(estilo.degrade))
            VStack(alignment: .leading, spacing: 2) {
                Text("Carregamento otimizado").font(.system(size: 14, weight: .semibold))
                Text("O macOS pode parar em 80% e terminar mais tarde.")
                    .font(.system(size: 13)).foregroundStyle(secundario)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.cartao))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(estilo.bordaCartao, lineWidth: 1))
    }

    private func linhas(_ s: Situacao) -> some View {
        var itens: [(String, String)] = [
            ("Corrente", Formato.comSinal(Double(s.leitura.correnteMa), casas: 0) + " mA"),
            ("Tensão", Formato.numero(Double(s.leitura.tensaoMv) / 1000, casas: 2) + " V"),
        ]
        if let t = s.detalhes.temperaturaC { itens.append(("Temperatura", Formato.numero(t, casas: 0) + " °C")) }
        if let saude = s.saudePercentual {
            var v = Formato.percentual(saude)
            if let c = s.detalhes.ciclos { v += " · \(c) ciclos" }
            itens.append(("Saúde", v))
        } else if let c = s.detalhes.ciclos {
            itens.append(("Saúde", "\(c) ciclos"))
        }
        if s.estado != .carregando {
            itens.append(("Modo de energia", s.detalhes.poucaEnergia ? "Pouca Energia" : "Normal"))
        }
        return VStack(spacing: 0) {
            ForEach(Array(itens.enumerated()), id: \.offset) { i, item in
                HStack {
                    Text(item.0).foregroundStyle(Color.primary.opacity(0.68))
                    Spacer()
                    Text(item.1).monospacedDigit()
                }
                .font(.system(size: 14))
                .padding(.vertical, 7)
                .overlay(alignment: .bottom) {
                    if i < itens.count - 1 { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.cartao))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(estilo.bordaCartao, lineWidth: 1))
    }

    private var rodape: some View {
        VStack(spacing: 14) {
            Button(action: acoes.maisInformacoes) {
                HStack(spacing: 8) {
                    Text("Mais informações").font(.system(size: 15, weight: .bold))
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .heavy))
                }
                .foregroundStyle(estilo.primeiroPlanoSelecionado)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(FundoSelecionavel(selecionado: true, raio: 22))
            }
            .buttonStyle(.plain)

            HStack {
                Button(action: acoes.preferencias) {
                    Text("Preferências…").font(.system(size: 15)).frame(minHeight: 32)
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: acoes.sair) {
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

/// Uma coluna do gráfico: média do ritmo num intervalo.
private struct BarraRitmo {
    var inicio: Date
    var duracao: TimeInterval
    var valor: Double

    /// Reparte os pontos dos últimos `minutos` em até 30 colunas, pela média.
    static func agrupar(_ serie: [PontoMinuto], fim: Date, minutos: Int) -> [BarraRitmo] {
        let n = min(30, minutos)
        let janela = Double(minutos) * 60
        let tamanho = janela / Double(n)
        let inicio = fim.addingTimeInterval(-janela)
        var somas = [Double](repeating: 0, count: n)
        var contagens = [Int](repeating: 0, count: n)
        for p in serie where p.data >= inicio && p.data <= fim {
            let i = min(n - 1, Int(p.data.timeIntervalSince(inicio) / tamanho))
            somas[i] += p.ritmo
            contagens[i] += 1
        }
        return (0..<n).compactMap { i in
            guard contagens[i] > 0 else { return nil }
            return BarraRitmo(inicio: inicio.addingTimeInterval(Double(i) * tamanho), duracao: tamanho,
                              valor: somas[i] / Double(contagens[i]))
        }
    }
}

/// O gráfico em si, separado para o compilador não se perder na expressão.
private struct GraficoBarras: View {
    @Environment(\.estilo) private var estilo
    let barras: [BarraRitmo]
    let carregando: Bool
    let teto: Double
    let media: Double?
    let inicio: Date
    let fim: Date
    let marcas: [Date]

    private struct Item: Identifiable {
        var id: Int
        var inicio: Date
        var fim: Date
        var altura: Double
        var cor: Color
    }

    private var itens: [Item] {
        barras.enumerated().map { i, b in
            Item(id: i, inicio: b.inicio, fim: b.inicio.addingTimeInterval(b.duracao * 0.88),
                 altura: abs(b.valor), cor: cor(b, i))
        }
    }

    var body: some View {
        Chart {
            ForEach(itens) { item in
                RectangleMark(
                    xStart: .value("Início", item.inicio),
                    xEnd: .value("Fim", item.fim),
                    yStart: .value("Base", 0.0),
                    yEnd: .value("Ritmo", item.altura)
                )
                .foregroundStyle(item.cor)
            }
            if let media {
                RuleMark(y: .value("Média", abs(media)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(estilo.destaqueTopo.opacity(0.9))
            }
        }
        .chartXScale(domain: inicio...fim)
        .chartYScale(domain: 0...teto)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: marcas) { _ in
                AxisValueLabel(format: formatoHora)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.55))
            }
        }
        .frame(height: 112)
    }

    private var formatoHora: Date.FormatStyle {
        Date.FormatStyle(locale: Locale(identifier: "pt_BR")).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
    }

    private func cor(_ b: BarraRitmo, _ i: Int) -> Color {
        if carregando {
            if b.valor < 0 { return Color.primary.opacity(0.28) }
            return i >= barras.count - 3 ? estilo.destaque : estilo.destaque.opacity(0.6)
        }
        return i >= barras.count - 5 ? estilo.destaque : estilo.destaque.opacity(0.55)
    }
}
