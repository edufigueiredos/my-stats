import SwiftUI

// Painel da CPU (docs/desenho/modulos/PainelCPU.dc.html) e as peças que os painéis de GPU e Memória também usam.

// MARK: - Peças compartilhadas pelos painéis de CPU, GPU e Memória

/// Anel de 92 com o número no centro (21 bold) e um rótulo embaixo (11).
struct AnelCentroPainel: View {
    let fracao: Double
    let centro: String
    let sub: String
    var lado: CGFloat = 92
    var espessura: CGFloat = 8
    @Environment(\.estilo) private var estilo

    var body: some View {
        ZStack {
            Circle().inset(by: espessura / 2).stroke(Color.primary.opacity(0.10), lineWidth: espessura)
            Circle().inset(by: espessura / 2)
                .trim(from: 0, to: CGFloat(min(max(fracao, 0), 1)))
                .stroke(estilo.destaque, style: StrokeStyle(lineWidth: espessura, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(centro).font(.system(size: 21, weight: .bold)).monospacedDigit()
                Text(sub).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.62)).monospacedDigit()
            }
        }
        .frame(width: lado, height: lado)
    }
}

/// "Quem mais usa": cabeçalho com dica e um cartão de linhas. Sem itens, some.
struct SecaoProcessosPainel: View {
    let dica: String
    let itens: [(nome: String, valor: String, fracao: Double?)]

    var body: some View {
        if !itens.isEmpty {
            VStack(spacing: 14) {
                CabecalhoSecao("Quem mais usa", dica: dica).padding(.top, 2)
                Cartao(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(itens.indices, id: \.self) { i in
                            LinhaProcesso(indice: i, nome: itens[i].nome, valor: itens[i].valor, fracao: itens[i].fracao)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

/// Rodapé dos painéis de módulo: botão de abrir o app, "Visão geral" e "Sair".
struct RodapePainelModulo: View {
    let modulo: Modulo
    let acoes: AcoesModulo

    var body: some View {
        RodapeModulo(tituloBotao: modulo.tituloAbrirApp, acaoBotao: acoes.abrirApp,
                     textoEsquerda: "Visão geral", acaoEsquerda: acoes.visaoGeral, sair: acoes.sair)
    }
}

/// Início, meio e "agora" do eixo de um gráfico que cobre `janela` segundos até `agora`.
func rotulosEixoPainel(janela: TimeInterval, agora: Date) -> [String] {
    [Formato.horario(agora.addingTimeInterval(-janela)), Formato.horario(agora.addingTimeInterval(-janela / 2)), "agora"]
}

/// Número grande de uso com o "%" ao lado.
struct NumeroUsoPainel: View {
    @Environment(\.estilo) private var estilo
    let texto: String
    var corpo: CGFloat = 46
    var unidade: String? = "%"
    var corUnidade: CGFloat = 20

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(texto).font(.system(size: corpo, weight: .bold)).tracking(-corpo * 0.03).foregroundStyle(estilo.destaqueTopo)
            if let unidade {
                Text(unidade).font(.system(size: corUnidade, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.75))
            }
        }
        .monospacedDigit()
        .lineLimit(1)
    }
}

/// Cartão de gráfico com o eixo de tempo embaixo.
struct CartaoGraficoPainel<Grafico: View>: View {
    let eixo: [String]
    let grafico: Grafico
    init(eixo: [String], @ViewBuilder grafico: () -> Grafico) {
        self.eixo = eixo
        self.grafico = grafico()
    }

    var body: some View {
        Cartao {
            VStack(spacing: 6) {
                grafico
                EixoTempo(eixo)
            }
        }
    }
}

/// Faixa de uso da CPU pelo valor médio.
private enum FaixaCPU: Equatable {
    case tranquila, moderada, puxada
    init(_ v: Double) { self = v < 30 ? .tranquila : (v <= 70 ? .moderada : .puxada) }
    var titulo: String {
        switch self {
        case .tranquila: return "Tranquila"
        case .moderada: return "Moderada"
        case .puxada: return "Puxada"
        }
    }
}

// MARK: - Painel

struct PainelCPU: View {
    let leituras: LeiturasModulos
    let series: SeriesModulos
    let acoes: AcoesModulo
    var alturaMaxima: CGFloat? = nil
    @State private var periodo: PeriodoModulo
    @Environment(\.estilo) private var estilo

    init(leituras: LeiturasModulos, series: SeriesModulos, acoes: AcoesModulo, alturaMaxima: CGFloat? = nil,
         periodoInicial: PeriodoModulo = .dezMin) {
        self.leituras = leituras
        self.series = series
        self.acoes = acoes
        self.alturaMaxima = alturaMaxima
        _periodo = State(initialValue: periodoInicial)
    }

    private var agora: Date { leituras.data }
    private var cpu: LeituraCPU? { leituras.cpu }

    var body: some View {
        MolduraPainelModulo(alturaMaxima: alturaMaxima) {
            CabecalhoModulo(icone: .cpu, titulo: "CPU", subtitulo: subtitulo, corPonto: corPonto,
                            rotuloPreferencias: "Preferências da CPU", aoPreferencias: acoes.preferencias)
            cartaoUso
            ChipsPeriodo(selecao: periodo, aoEscolher: { periodo = $0 })
            historico
            nucleos
            SecaoProcessosPainel(dica: "100% = 1 núcleo", itens: processos)
            CartaoLinhas(linhas)
        } rodape: {
            RodapePainelModulo(modulo: .cpu, acoes: acoes)
        }
    }

    // MARK: Cabeçalho

    /// Média do último minuto, ou o valor atual quando a série ainda está vazia.
    private var mediaUltimoMinuto: Double? {
        let v = series.valores(.cpuUso, janela: 60, colunas: 1, agora: agora)
        return v.first.flatMap { $0 } ?? cpu?.uso
    }

    private var subtitulo: String {
        guard let media = mediaUltimoMinuto else { return "Sem leitura" }
        let faixa = FaixaCPU(media)
        var texto = faixa.titulo
        // Desde quando a série está nessa faixa, em colunas de 1 min (até 1 h).
        let minutos = series.valores(.cpuUso, janela: 3_600, colunas: 60, agora: agora)
        var n = 0
        for v in minutos.reversed() {
            guard let v, FaixaCPU(v) == faixa else { break }
            n += 1
        }
        if n >= 2 { texto += " há \(n) min" }
        if let nucleos = cpu?.nucleos.count, nucleos > 0 { texto += " · \(nucleos) núcleos" }
        return texto
    }

    private var corPonto: Color {
        guard let media = mediaUltimoMinuto else { return Color.primary.opacity(0.3) }
        return FaixaCPU(media) == .puxada ? estilo.destaqueTopo : Paleta.bom
    }

    // MARK: Uso

    private var cartaoUso: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Uso agora")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.primary.opacity(0.6))
                NumeroUsoPainel(texto: cpu.map { Formato.inteiro(Int($0.uso.rounded())) } ?? Formato.semDado,
                                unidade: cpu == nil ? nil : "%")
                BarraSegmentos(partes: [((cpu?.usuario ?? 0) / 100, estilo.destaque),
                                        ((cpu?.sistema ?? 0) / 100, Color.primary.opacity(0.45))], altura: 8)
                legenda
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            AnelCentroPainel(fracao: (cpu?.uso ?? 0) / 100,
                             centro: Formato.temperatura(leituras.sensores?.cpuC, curta: true),
                             sub: leituras.energia?.cpuW.map { Formato.numero($0, casas: $0 < 10 ? 1 : 0) + " W" } ?? "CPU")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(estilo.cartao))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(estilo.bordaCartao, lineWidth: 1))
    }

    private var legenda: some View {
        HStack(spacing: 12) {
            if let cpu {
                legendaItem(estilo.destaque, "Apps \(Formato.percentual(cpu.usuario))")
                legendaItem(Color.primary.opacity(0.45), "Sistema \(Formato.percentual(cpu.sistema))")
                Text("Livre \(Formato.percentual(max(0, 100 - cpu.usuario - cpu.sistema)))")
            } else {
                Text(Formato.semDado)
            }
        }
        .font(.system(size: 12))
        .monospacedDigit()
        .foregroundStyle(Color.primary.opacity(0.66))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func legendaItem(_ cor: Color, _ texto: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(cor).frame(width: 8, height: 8)
            Text(texto)
        }
    }

    // MARK: Histórico

    @ViewBuilder
    private var historico: some View {
        CartaoGraficoPainel(eixo: rotulosEixoPainel(janela: periodo.segundos, agora: agora)) {
            GraficoColunasEmpilhadas(
                baixo: series.valores(.cpuSistema, periodo: periodo, colunas: 30, agora: agora),
                cima: series.valores(.cpuApps, periodo: periodo, colunas: 30, agora: agora),
                maximo: 100, altura: 96,
                corBaixo: Color.primary.opacity(0.45), corCima: estilo.destaque)
        }
    }

    // MARK: Núcleos

    private var grupos: [(nome: String, valores: [Double])] {
        guard let cpu, !cpu.nucleos.isEmpty else { return [] }
        let n = cpu.nucleos
        let p = min(cpu.nucleosDesempenho, n.count)
        let e = min(cpu.nucleosEficiencia, n.count - p)
        if p == 0 && e == 0 { return [("Núcleos · \(n.count)", n)] }
        var r: [(String, [Double])] = []
        func nome(_ s: String?, padrao: String) -> String {
            switch s {
            case "Super": return "Super"
            case "Performance": return "Desempenho"
            case "Efficiency": return "Eficiência"
            case let t?: return t
            case nil: return padrao
            }
        }
        if p > 0 { r.append(("\(nome(cpu.nomeNivel0, padrao: "Desempenho")) · \(p)", Array(n[0..<p]))) }
        if e > 0 { r.append(("\(nome(cpu.nomeNivel1, padrao: "Eficiência")) · \(e)", Array(n[p..<(p + e)]))) }
        return r
    }

    @ViewBuilder
    private var nucleos: some View {
        let g = grupos
        if !g.isEmpty {
            VStack(spacing: 14) {
                CabecalhoSecao("Núcleos").padding(.top, 2)
                Cartao {
                    VStack(spacing: 10) {
                        ForEach(g.indices, id: \.self) { i in
                            VStack(spacing: 6) {
                                HStack {
                                    Text(g[i].nome)
                                    Spacer(minLength: 8)
                                    Text("média " + Formato.percentual(g[i].valores.reduce(0, +) / Double(g[i].valores.count)))
                                        .monospacedDigit()
                                }
                                .font(.system(size: 12))
                                .foregroundStyle(Color.primary.opacity(0.66))
                                HStack(alignment: .bottom, spacing: 4) {
                                    ForEach(g[i].valores.indices, id: \.self) { k in coluna(g[i].valores[k]) }
                                }
                                .frame(height: 40)
                            }
                        }
                    }
                }
            }
        }
    }

    private func coluna(_ v: Double) -> some View {
        let quente = v >= 90
        return ZStack(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.08))
            Rectangle()
                .fill(quente ? estilo.destaqueTopo : estilo.destaque)
                .opacity(quente ? 1 : 0.8)
                .frame(height: max(1, 40 * CGFloat(min(max(v, 0), 100) / 100)))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    // MARK: Processos e linhas

    private var processos: [(nome: String, valor: String, fracao: Double?)] {
        leituras.processos.cpu.prefix(4).map { ($0.nome, Formato.percentual($0.valor), $0.fracao) }
    }

    private var linhas: [(String, String)] {
        var r: [(String, String)] = []
        if let c = cpu {
            r.append(("Carga média", c.cargaMedia.isEmpty ? Formato.semDado
                      : c.cargaMedia.map { Formato.numero($0, casas: 1) }.joined(separator: " · ")))
        } else {
            r.append(("Carga média", Formato.semDado))
        }
        var temp = Formato.temperatura(leituras.sensores?.cpuC, curta: false)
        if leituras.sensores?.cpuC != nil, let maximo = series.maximo(.tempCPU, desde: agora.addingTimeInterval(-3_600)) {
            temp += " · máx. " + Formato.temperatura(maximo, curta: false)
        }
        r.append(("Temperatura", temp))
        // Sem leitura de potência da CPU (caso do M5), a linha some em vez de mostrar "—".
        if let w = leituras.energia?.cpuW { r.append(("Potência da CPU", Formato.numero(w, casas: w < 10 ? 1 : 0) + " W")) }
        if let n = cpu?.processos {
            var t = Formato.inteiro(n)
            if let th = cpu?.threads { t += " · \(Formato.inteiro(th)) threads" }
            r.append(("Processos", t))
        } else {
            r.append(("Processos", Formato.semDado))
        }
        r.append(("Ligado há", leituras.ligadoDesde.map { Formato.duracaoLonga(agora.timeIntervalSince($0)) } ?? Formato.semDado))
        return r
    }
}
