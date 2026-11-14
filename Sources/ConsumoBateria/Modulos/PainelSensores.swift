import SwiftUI

// Painel do módulo Sensores (docs/desenho/modulos/PainelSensores.dc.html). Dados de LeiturasModulos/SeriesModulos.

struct PainelSensores: View {
    @Environment(\.estilo) private var estilo
    let leituras: LeiturasModulos
    let series: SeriesModulos
    let acoes: AcoesModulo
    var avisoTitulo: String? = nil
    var avisoDica: String? = nil
    var alturaMaxima: CGFloat? = nil
    var todosAbertos = false

    @State private var verTodos: Bool

    init(leituras: LeiturasModulos, series: SeriesModulos, acoes: AcoesModulo, avisoTitulo: String? = nil, avisoDica: String? = nil,
         alturaMaxima: CGFloat? = nil, todosAbertos: Bool = false) {
        self.leituras = leituras
        self.series = series
        self.acoes = acoes
        self.avisoTitulo = avisoTitulo
        self.avisoDica = avisoDica
        self.alturaMaxima = alturaMaxima
        self.todosAbertos = todosAbertos
        _verTodos = State(initialValue: todosAbertos)
    }

    private var sensores: LeituraSensores? { leituras.sensores }

    private struct LinhaTemp: Identifiable {
        var id: String
        var nome: String
        var valor: Double
        var maximo: Double
    }

    var body: some View {
        MolduraPainelModulo(alturaMaxima: alturaMaxima) {
            CabecalhoModulo(icone: .sensores, titulo: "Sensores", subtitulo: subtitulo, corPonto: corPonto,
                            rotuloPreferencias: "Preferências dos sensores", aoPreferencias: acoes.preferencias)

            cartaoPotencia

            CabecalhoSecao("Temperaturas", dica: "agora · máx. 1 h").padding(.top, 2)
            cartaoTemperaturas

            if let fans = sensores?.ventoinhas, !fans.isEmpty {
                CabecalhoSecao("Ventoinhas").padding(.top, 2)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(fans) { v in cartaoVentoinha(v) }
                }
            }

            cartaoAviso
        } rodape: {
            RodapeModulo(tituloBotao: verTodos ? "Ver menos" : "Ver todos os sensores", acaoBotao: { verTodos.toggle() },
                         textoEsquerda: "Visão geral", acaoEsquerda: acoes.visaoGeral, sair: acoes.sair)
        }
    }

    // MARK: Cabeçalho

    private var mediaVentoinhas: Double? {
        let f = sensores?.ventoinhas.compactMap(\.fracao) ?? []
        return f.isEmpty ? nil : f.reduce(0, +) / Double(f.count)
    }

    private var subtitulo: String {
        var partes: [String] = []
        if let c = sensores?.cpuC { partes.append(c >= 85 ? "CPU quente" : (c >= 70 ? "CPU morna" : "CPU fria")) }
        if let m = mediaVentoinhas {
            partes.append("ventoinhas em \(Formato.percentual(m * 100))")
        } else {
            partes.append("sem ventoinhas")
        }
        return partes.joined(separator: " · ")
    }

    private var corPonto: Color {
        (sensores?.cpuC ?? 0) >= 70 ? estilo.destaqueTopo : Paleta.bom
    }

    // MARK: Potência

    private var cartaoPotencia: some View {
        let sistema = sensores?.sistemaW
        let cpu = leituras.energia?.cpuW, gpu = leituras.energia?.gpuW, tela = sensores?.telaW
        let conhecidas = (cpu ?? 0) + (gpu ?? 0) + (tela ?? 0)
        let resto = sistema.map { max($0 - conhecidas, 0) }
        let corCPU = estilo.destaque, corGPU = Color(hex: "#F7E3B5"), corTela = Color(hex: "#9B7A3C"), corResto = Color.white.opacity(0.32)
        let itens: [(nome: String, w: Double?, cor: Color)] = [
            ("CPU", cpu, corCPU), ("GPU", gpu, corGPU), ("Tela", tela, corTela), ("Resto do Mac", resto, corResto),
        ]
        func texto(_ w: Double?) -> String { w.map { Formato.numero($0, casas: $0 < 10 ? 1 : 0) + " W" } ?? Formato.semDado }
        let partes: [(fracao: Double, cor: Color)] = itens.compactMap { item in
            guard let w = item.w, let s = sistema, s > 0 else { return nil }
            return (w / s, item.cor)
        }
        return Cartao(padding: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        RotuloSecao("O Mac está puxando")
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(sistema.map { Formato.numero($0, casas: 0) } ?? Formato.semDado)
                                .font(.system(size: 46, weight: .bold)).tracking(-1.4).foregroundStyle(estilo.destaqueTopo)
                            if sistema != nil {
                                Text("W").font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.75))
                            }
                        }
                        .monospacedDigit()
                    }
                    Spacer(minLength: 8)
                    if sistema != nil {
                        Text(sensores?.carregadorW.map { "da tomada · carregador de \(Formato.numero($0, casas: 0)) W" } ?? "da bateria")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.primary.opacity(0.7))
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 8)
                    }
                }
                BarraSegmentos(partes: partes, altura: 10)
                LegendaSegmentos(itens: itens.map { ($0.cor, $0.nome, texto($0.w)) }, colunas: 2)
            }
            .padding(16)
        }
    }

    // MARK: Temperaturas

    private var linhasTemperatura: [LinhaTemp] {
        guard let s = sensores else { return [] }
        let desde = leituras.data.addingTimeInterval(-3_600)
        let base: [(String, String, Double?, MetricaSerie)] = [
            ("cpu", "CPU · média dos núcleos", s.cpuC, .tempCPU),
            ("gpu", "GPU", s.gpuC, .tempGPU),
            ("memoria", "Memória", s.memoriaC, .tempMemoria),
            ("ssd", "SSD", s.ssdC, .tempSSD),
            ("bateria", "Bateria", s.bateriaC, .tempBateria),
            ("ar", "Ar interno", s.arC, .tempAr),
        ]
        var linhas: [LinhaTemp] = base.compactMap { id, nome, v, metrica in
            guard let v else { return nil }
            return LinhaTemp(id: id, nome: nome, valor: v, maximo: max(series.maximo(metrica, desde: desde) ?? v, v))
        }
        if verTodos {
            let usados = Set(linhas.map(\.nome))
            let extras = s.todas
                .filter { !usados.contains($0.nome) }
                .sorted { $0.nome.localizedCaseInsensitiveCompare($1.nome) == .orderedAscending }
            linhas += extras.map { LinhaTemp(id: "todas-" + $0.id, nome: $0.nome, valor: $0.valorC, maximo: $0.valorC) }
        }
        return linhas
    }

    @ViewBuilder
    private var cartaoTemperaturas: some View {
        let linhas = linhasTemperatura
        Cartao(padding: 0) {
            if linhas.isEmpty {
                Text("Não consegui ler os sensores deste Mac")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary.opacity(0.62))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(linhas) { l in linhaTemperatura(l) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
    }

    private func linhaTemperatura(_ l: LinhaTemp) -> some View {
        let quente = l.valor >= 85, morna = l.valor >= 70
        let cor: Color = quente ? .quenteModulo : (morna ? estilo.destaqueTopo : Color.primary)
        let largura = min(max((l.valor - 20) / 90, 0), 1)
        return VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(l.nome).font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.75)).lineLimit(1)
                Spacer(minLength: 8)
                Text(Formato.temperatura(l.valor, curta: true))
                    .font(.system(size: 15, weight: quente ? .heavy : .semibold)).monospacedDigit().foregroundStyle(cor)
                Text("máx. " + Formato.temperatura(l.maximo, curta: true))
                    .font(.system(size: 12)).monospacedDigit().foregroundStyle(Color.primary.opacity(0.55))
                    .frame(width: 52, alignment: .trailing)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 2).fill(quente ? Color.quenteModulo : estilo.destaque)
                        .frame(width: g.size.width * CGFloat(largura))
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 8)
    }

    // MARK: Ventoinhas e aviso

    private func cartaoVentoinha(_ v: Ventoinha) -> some View {
        Cartao(padding: 12) {
            HStack(spacing: 10) {
                AnelModulo(fracao: v.fracao ?? 0, lado: 32, espessura: 4, cor: estilo.destaque, centro: nil, sub: nil)
                VStack(alignment: .leading, spacing: 2) {
                    Text(v.nome).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.62)).lineLimit(1)
                    Text(Formato.rpm(v.rpm)).font(.system(size: 17, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    if let f = v.fracao {
                        Text("\(Formato.percentual(f * 100)) da rotação máxima")
                            .font(.system(size: 11)).monospacedDigit().foregroundStyle(Color.primary.opacity(0.55)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var cartaoAviso: some View {
        Cartao(padding: 12) {
            HStack(spacing: 12) {
                Image(systemName: "bell")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(estilo.sobreDestaque)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(estilo.degrade))
                VStack(alignment: .leading, spacing: 2) {
                    Text(avisoTitulo ?? "Avisos de temperatura desligados").font(.system(size: 14, weight: .semibold))
                    Text(avisoDica ?? "Ligue nas Preferências.").font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.62))
                }
                Spacer(minLength: 0)
            }
        }
    }
}
