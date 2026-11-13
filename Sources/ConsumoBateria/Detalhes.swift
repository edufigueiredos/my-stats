import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers

// Janela "Mais informações", fiel a docs/desenho/Detalhes.dc.html (1240 x 860, barra lateral de 230).
// Só controles desenhados (nada de Picker, Toggle ou Table nativos) para o ImageRenderer.

enum SecaoDetalhes: CaseIterable, Identifiable {
    case visaoGeral, historico, apps, saude, alertas

    var id: Self { self }

    var titulo: String {
        switch self {
        case .visaoGeral: return "Visão geral"
        case .historico: return "Histórico"
        case .apps: return "Apps"
        case .saude: return "Saúde da bateria"
        case .alertas: return "Alertas"
        }
    }

    var simbolo: String {
        switch self {
        case .visaoGeral: return "square.grid.2x2"
        case .historico: return "chart.xyaxis.line"
        case .apps: return "square.stack.3d.up"
        case .saude: return "heart"
        case .alertas: return "bell"
        }
    }

    /// Saúde e alertas não dependem do período.
    var usaPeriodo: Bool { self != .saude && self != .alertas }
}

struct JanelaDetalhes: View {
    let historico: Historico
    let situacao: Situacao?
    var secaoInicial: SecaoDetalhes = .visaoGeral
    var periodoInicial: Periodo = .hoje
    var paraFoto = false

    @Environment(\.estilo) private var estilo
    @State private var secao: SecaoDetalhes
    @State private var periodo: Periodo
    /// Dados pesados do histórico, recalculados só quando muda o período ou passa 1 minuto.
    @State private var cache = CacheDados()

    init(historico: Historico, situacao: Situacao?, secaoInicial: SecaoDetalhes = .visaoGeral,
         periodoInicial: Periodo = .hoje, paraFoto: Bool = false) {
        self.historico = historico
        self.situacao = situacao
        self.secaoInicial = secaoInicial
        self.periodoInicial = periodoInicial
        self.paraFoto = paraFoto
        _secao = State(initialValue: secaoInicial)
        _periodo = State(initialValue: periodoInicial)
    }

    var body: some View {
        HStack(spacing: 0) {
            barraLateral
            Rectangle().fill(Color.primary.opacity(0.07)).frame(width: 1)
            if paraFoto {
                conteudo(agora: situacao?.leitura.data ?? Date())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                // Recalcula a cada minuto com a janela aberta.
                TimelineView(.periodic(from: .now, by: 60)) { contexto in
                    ScrollView { conteudo(agora: contexto.date) }
                }
            }
        }
        .frame(width: paraFoto ? 1240 : nil, height: paraFoto ? 860 : nil)
        .frame(minWidth: paraFoto ? nil : 1000, minHeight: paraFoto ? nil : 700)
    }

    // MARK: Barra lateral

    private var barraLateral: some View {
        VStack(alignment: .leading, spacing: 4) {
            if paraFoto {
                HStack(spacing: 8) {
                    ForEach(["#FF5F57", "#FEBC2E", "#28C840"], id: \.self) { hex in
                        Circle().fill(Color(hex: hex)).frame(width: 12, height: 12)
                    }
                }
                .padding(.horizontal, 6).padding(.bottom, 18)
            } else {
                Spacer().frame(height: 22)
            }
            ForEach(SecaoDetalhes.allCases) { item in
                let ativa = item == secao
                Button { secao = item } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.simbolo).font(.system(size: 13)).frame(width: 18)
                        Text(item.titulo).font(.system(size: 14, weight: ativa ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .foregroundStyle(ativa ? estilo.primeiroPlanoSelecionado : Color.primary.opacity(0.8))
                    .background { if ativa { FundoSelecionavel(selecionado: true, raio: 8) } }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(ativa ? .isSelected : [])
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                Text("Guardando histórico").font(.system(size: 12)).foregroundStyle(.secondary)
                Text("Uma leitura por minuto · \(Ajustes.compartilhado.diasHistorico) dias")
                    .font(.system(size: 13)).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(estilo.cartao))
        }
        .padding(.horizontal, 12).padding(.vertical, 16)
        .frame(width: 230)
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(0.035))
    }

    // MARK: Conteúdo

    private struct Dados {
        var resumo: ResumoPeriodo
        /// Em ordem cronológica, só "Na bateria" e "Carregando".
        var trechos: [Trecho]
        var faixas: [Trecho]
        var pontos: [PontoMinuto]
        var apps: [GastoApp]
    }

    private final class CacheDados {
        var chave: String?
        var dados: Dados?
    }

    /// Reaproveita os dados enquanto o período e o minuto são os mesmos; a leitura ao vivo de 5 s não relê o disco.
    private func carregar(agora: Date) -> Dados {
        let chave = "\(periodo.rawValue)|\(Int(agora.timeIntervalSince1970 / 60))"
        if cache.chave == chave, let dados = cache.dados { return dados }
        let iv = periodo.intervalo(ate: agora)
        let pontos = historico.pontos(de: iv.start, ate: iv.end)
        let todos = Array(historico.trechos(pontos: pontos).reversed())
        let dados = Dados(
            resumo: historico.resumo(pontos: pontos),
            trechos: todos.filter { $0.tipo != .naTomadaParado },
            faixas: todos.filter { $0.tipo != .naBateria },
            pontos: amostrar(pontos),
            apps: historico.quemMaisGastou(periodo))
        cache.chave = chave
        cache.dados = dados
        return dados
    }

    /// No máximo ~400 pontos no gráfico.
    private func amostrar(_ pontos: [PontoMinuto]) -> [PontoMinuto] {
        let passo = max(1, pontos.count / 400)
        guard passo > 1 else { return pontos }
        var saida = stride(from: 0, to: pontos.count, by: passo).map { pontos[$0] }
        if let ultimo = pontos.last, saida.last != ultimo { saida.append(ultimo) }
        return saida
    }

    private func conteudo(agora: Date) -> some View {
        let dados = carregar(agora: agora)
        return VStack(alignment: .leading, spacing: 18) {
            cabecalho(agora: agora)
            switch secao {
            case .visaoGeral:
                numeros(dados.resumo)
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 14) {
                        cartaoGrafico(dados, agora: agora, altura: 220)
                        cartaoTrechos(dados, agora: agora, limite: periodo == .hoje ? 4 : 5)
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 14) {
                        cartaoApps(dados.apps, ampliado: false)
                        cartaoSaude(ampliado: false)
                        botaoExportar
                    }
                    .frame(width: 300)
                }
            case .historico:
                cartaoGrafico(dados, agora: agora, altura: 300)
                cartaoTrechos(dados, agora: agora, limite: nil)
                HStack { Spacer(); botaoExportar.frame(width: 300) }
            case .apps:
                cartaoApps(dados.apps, ampliado: true)
            case .saude:
                cartaoSaude(ampliado: true)
            case .alertas:
                cartaoAlertas
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func cabecalho(agora: Date) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(secao == .visaoGeral ? periodo.titulo : secao.titulo)
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.5)
                Text(subtitulo(agora: agora))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if secao.usaPeriodo {
                LinhaChips(opcoes: Periodo.allCases.map { .init(valor: $0, titulo: $0.titulo) },
                           selecao: periodo) { periodo = $0 }
                    .padding(3)
                    .frame(width: 270)
                    .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(estilo.cartao))
            }
        }
    }

    private func subtitulo(agora: Date) -> String {
        var partes: [String] = []
        let br = Locale(identifier: "pt_BR")
        if secao == .visaoGeral || secao == .historico || secao == .apps {
            if periodo == .hoje {
                partes.append(agora.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(br)))
            } else {
                partes.append("últimos \(periodo.dias) dias")
            }
        } else if secao == .saude {
            partes.append("capacidade e desgaste")
        } else {
            partes.append("avisos ligados em Preferências")
        }
        if let s = situacao {
            var agoraTxt = "agora \(s.leitura.percentual)%"
            let ajustes = Ajustes.compartilhado
            switch s.estado {
            case .descarregando, .alto:
                agoraTxt += ", gastando \(Formato.ritmo(abs(s.ritmoMedio ?? s.ritmoAgora), casas: ajustes.casasDecimais, sentido: .soCor))"
            case .carregando:
                agoraTxt += ", carregando \(Formato.ritmo(s.ritmoMedio ?? s.ritmoAgora, casas: ajustes.casasDecimais, sentido: .soCor))"
            default: break
            }
            if secao == .visaoGeral || secao == .historico || secao == .apps { partes.append(agoraTxt) }
        }
        return partes.joined(separator: " · ")
    }

    // MARK: Os 4 números

    private func numeros(_ r: ResumoPeriodo) -> some View {
        let ajustes = Ajustes.compartilhado
        func ritmo(_ v: Double?) -> String {
            Formato.ritmo(v, casas: ajustes.casasDecimais, sentido: ajustes.sentido)
        }
        let ouro = estilo.destaqueTopo
        let quente = Color(hex: "#FFB340")
        let piorHora = r.piorHoraInicio.map { "\(hhmm($0)) às \(hhmm($0.addingTimeInterval(3600)))" } ?? "sem dados"
        let w = r.wattsMedioBateria.map { "\(Formato.numero($0)) W em média" } ?? "sem dados"
        let desde: String = {
            guard let d = r.desde else { return "sem dados" }
            if Calendar.current.isDateInToday(d) { return "desde \(hhmm(d))" }
            return "desde \(d.formatted(.dateTime.day().month(.twoDigits).locale(Locale(identifier: "pt_BR"))))"
        }()
        let vezes = r.cargas == 0 ? "Nenhuma" : (r.cargas == 1 ? "1 vez" : "\(r.cargas) vezes")
        let ganho = r.cargas == 0 ? "no período" : "+\(Int(r.ganhoCarga.rounded()))% em \(duracaoCurta(minutos: r.minutosCarregando))"
        let itens: [(String, String, String, Color)] = [
            ("Média na bateria", ritmo(r.ritmoMedioBateria), w, ouro),
            ("Pior hora", ritmo(r.piorHoraRitmo), piorHora, quente),
            ("Tempo na bateria", r.tempoNaBateria > 0 ? duracaoHoras(r.tempoNaBateria) : "–", desde, .primary),
            ("Carregou", vezes, ganho, .primary),
        ]
        return HStack(spacing: 10) {
            ForEach(itens.indices, id: \.self) { i in
                let item = itens[i]
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0).font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(item.1).font(.system(size: 24, weight: .bold)).monospacedDigit()
                        .foregroundStyle(item.3)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(item.2).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.cartao))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(estilo.bordaCartao, lineWidth: 1))
            }
        }
    }

    private func hhmm(_ d: Date) -> String { Formato.horario(d) }

    private func duracaoHoras(_ segundos: TimeInterval) -> String {
        let m = Int((segundos / 60).rounded())
        return m >= 60 ? "\(m / 60)h\(String(format: "%02d", m % 60))" : "\(m) min"
    }

    private func duracaoCurta(minutos: Double) -> String {
        let m = Int(minutos.rounded())
        return m >= 60 ? "\(m / 60)h\(String(format: "%02d", m % 60))" : "\(m) min"
    }

    // MARK: Gráfico da carga

    private struct Previsao {
        var agora: Date
        var percentual: Double
        var fim: Date
    }

    private func previsao() -> Previsao? {
        guard periodo == .hoje, let s = situacao, s.estado == .descarregando || s.estado == .alto,
              let fim = s.horarioFim, fim > s.leitura.data, s.leitura.percentual > 0 else { return nil }
        return Previsao(agora: s.leitura.data, percentual: Double(s.leitura.percentual), fim: fim)
    }

    private func dominio(_ dados: Dados, agora: Date, previsao: Previsao?) -> ClosedRange<Date> {
        let cal = Calendar.current
        let iv = periodo.intervalo(ate: agora)
        var inicio = iv.start
        var fim = agora
        if periodo == .hoje {
            if let primeiro = dados.pontos.first(where: { !$0.naTomada }) {
                let hora = cal.dateInterval(of: .hour, for: primeiro.data)?.start ?? primeiro.data
                inicio = max(iv.start, hora.addingTimeInterval(-3600))
            }
            if let p = previsao { fim = max(fim, p.fim) }
            fim = cal.dateInterval(of: .hour, for: fim)?.end.addingTimeInterval(3600) ?? fim.addingTimeInterval(3600)
        }
        if fim <= inicio { fim = inicio.addingTimeInterval(3600) }
        return inicio...fim
    }

    private func cartaoGrafico(_ dados: Dados, agora: Date, altura: CGFloat) -> some View {
        let prev = previsao()
        let faixaX = dominio(dados, agora: agora, previsao: prev)
        let ouro = estilo.destaque
        let curtoDia = periodo == .hoje
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                RotuloSecao("Carga da bateria")
                Spacer()
                HStack(spacing: 14) {
                    legenda(Rectangle().fill(ouro).frame(width: 14, height: 2), "Carga")
                    legenda(Rectangle().stroke(ouro.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [3, 2.5]))
                        .frame(width: 14, height: 2), "Previsão")
                    legenda(RoundedRectangle(cornerRadius: 2).fill(Paleta.bom.opacity(0.25)).frame(width: 10, height: 10),
                            "Na tomada")
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.65))
            }
            Chart {
                ForEach(dados.faixas) { f in
                    RectangleMark(xStart: .value("De", max(f.inicio, faixaX.lowerBound)),
                                  xEnd: .value("Até", min(f.fim, faixaX.upperBound)),
                                  yStart: .value("Mín", 0), yEnd: .value("Máx", 100))
                        .foregroundStyle(Paleta.bom.opacity(0.18))
                }
                ForEach(Array(dados.pontos.filter { faixaX.contains($0.data) }.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("Hora", p.data), y: .value("Carga", p.percentual),
                             series: .value("Série", "carga"))
                        .foregroundStyle(ouro)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
                if let p = prev {
                    LineMark(x: .value("Hora", p.agora), y: .value("Carga", p.percentual),
                             series: .value("Série", "previsao"))
                        .foregroundStyle(ouro.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    LineMark(x: .value("Hora", p.fim), y: .value("Carga", 0),
                             series: .value("Série", "previsao"))
                        .foregroundStyle(ouro.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    PointMark(x: .value("Hora", p.fim), y: .value("Carga", 0))
                        .symbolSize(30)
                        .foregroundStyle(ouro.opacity(0.7))
                        .annotation(position: .top, alignment: .trailing, spacing: 4) {
                            Text("\(hhmm(p.fim)) · acaba")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    RuleMark(x: .value("Agora", p.agora), yStart: .value("Mín", 0), yEnd: .value("Máx", 100))
                        .foregroundStyle(Color.primary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            }
            .chartXScale(domain: faixaX)
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { valor in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.primary.opacity(valor.as(Int.self) == 0 ? 0.14 : 0.07))
                    AxisValueLabel {
                        Text("\(valor.as(Int.self) ?? 0)%").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            .chartXAxis {
                if curtoDia {
                    AxisMarks(values: .stride(by: .hour, count: 2)) { valor in
                        AxisValueLabel {
                            if let d = valor.as(Date.self) {
                                Text(hhmm(d)).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    AxisMarks(values: .stride(by: .day, count: periodo == .seteDias ? 1 : 5)) { valor in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.primary.opacity(0.05))
                        AxisValueLabel {
                            if let d = valor.as(Date.self) {
                                Text(d.formatted(.dateTime.day().month(.twoDigits).locale(Locale(identifier: "pt_BR"))))
                                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .chartPlotStyle { $0.clipped() }
            .frame(height: altura)
            .overlay {
                if dados.pontos.isEmpty {
                    Text("Sem leituras neste período ainda.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.cartao))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(estilo.bordaCartao, lineWidth: 1))
    }

    private func legenda<F: View>(_ marca: F, _ texto: String) -> some View {
        HStack(spacing: 5) { marca; Text(texto) }
    }

    // MARK: Tabela de trechos

    private func cartaoTrechos(_ dados: Dados, agora: Date, limite: Int?) -> some View {
        let ordenados = periodo == .hoje ? dados.trechos : Array(dados.trechos.reversed())
        let visiveis: [Trecho] = {
            guard let limite, ordenados.count > limite else { return ordenados }
            return periodo == .hoje ? Array(ordenados.suffix(limite)) : Array(ordenados.prefix(limite))
        }()
        let larguraHorario: CGFloat = periodo == .hoje ? 120 : 160
        let ajustes = Ajustes.compartilhado
        return VStack(alignment: .leading, spacing: 8) {
            RotuloSecao(periodo == .hoje ? "Trechos do dia" : "Trechos do período")
            linhaTabela(larguraHorario: larguraHorario, cabecalho: true,
                        c: ("Horário", AnyView(Text("Estado")), AnyView(Text("Carga")), "Ritmo", "Média"))
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).padding(.top, -4)
            if visiveis.isEmpty {
                Text("Nenhum trecho neste período ainda.").font(.system(size: 13)).foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
            ForEach(visiveis) { t in
                let carregando = t.tipo == .carregando
                let cor: Color = carregando ? (estilo.scheme == .light ? Paleta.bom : Color(hex: "#7EE2A0")) : estilo.destaqueTopo
                linhaTabela(larguraHorario: larguraHorario, cabecalho: false, c: (
                    horario(t, agora: agora),
                    AnyView(HStack(spacing: 6) {
                        Circle().fill(carregando ? Paleta.bom : Color(hex: "#FFB340")).frame(width: 7, height: 7)
                        Text(t.tipo.titulo)
                    }),
                    AnyView(Text("\(Formato.percentual(t.percentualInicio)) → \(Formato.percentual(t.percentualFim))")),
                    Formato.ritmo(t.ritmoMedio, casas: ajustes.casasDecimais, sentido: ajustes.sentido == .setas ? .setas : .sinais),
                    Formato.watts(t.wattsMedio)), corRitmo: cor)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.cartao))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(estilo.bordaCartao, lineWidth: 1))
    }

    private func linhaTabela(larguraHorario: CGFloat, cabecalho: Bool,
                             c: (String, AnyView, AnyView, String, String), corRitmo: Color = .primary) -> some View {
        HStack(spacing: 12) {
            Text(c.0).frame(width: larguraHorario, alignment: .leading)
            c.1.frame(width: 120, alignment: .leading)
            c.2.frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
            Text(c.3).fontWeight(cabecalho ? .regular : .semibold)
                .foregroundStyle(cabecalho ? Color.primary.opacity(0.55) : corRitmo)
                .frame(width: 100, alignment: .trailing)
            Text(c.4).foregroundStyle(cabecalho ? Color.primary.opacity(0.55) : Color.primary.opacity(0.75))
                .frame(width: 80, alignment: .trailing)
        }
        .font(.system(size: cabecalho ? 13 : 14))
        .monospacedDigit()
        .lineLimit(1)
        .foregroundStyle(cabecalho ? Color.primary.opacity(0.55) : Color.primary)
        .padding(.vertical, cabecalho ? 0 : 3)
    }

    private func horario(_ t: Trecho, agora: Date) -> String {
        let cal = Calendar.current
        let emAndamento = agora.timeIntervalSince(t.fim) < 150
        let fim = emAndamento ? "agora" : hhmm(t.fim)
        var texto = "\(hhmm(t.inicio)) – \(fim)"
        if periodo != .hoje {
            let dia = t.inicio.formatted(.dateTime.day().month(.twoDigits).locale(Locale(identifier: "pt_BR")))
            texto = "\(dia) \(texto)"
            if !cal.isDate(t.inicio, inSameDayAs: t.fim) && !emAndamento { texto = "\(dia) \(hhmm(t.inicio)) → \(hhmm(t.fim))" }
        }
        return texto
    }

    // MARK: Quem mais gastou

    private func cartaoApps(_ apps: [GastoApp], ampliado: Bool) -> some View {
        let maior = max(apps.map(\.wh).max() ?? 1, 0.1)
        return VStack(alignment: .leading, spacing: ampliado ? 12 : 8) {
            HStack(alignment: .firstTextBaseline) {
                RotuloSecao("Quem mais gastou")
                Spacer()
                Text("Wh \(periodo == .hoje ? "hoje" : "em \(periodo.titulo.lowercased())"), estimado")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if apps.isEmpty {
                Text("Ainda sem dados de apps neste período.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            ForEach(apps) { app in
                HStack(spacing: 10) {
                    Text(app.nome == "Outros" ? "+" : String(app.nome.prefix(1)).uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: "#1F1505"))
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(corDoApp(app.nome)))
                    VStack(spacing: 3) {
                        HStack {
                            Text(app.nome).lineLimit(1)
                            Spacer(minLength: 6)
                            Text("\(Formato.numero(app.wh)) Wh").monospacedDigit().foregroundStyle(Color.primary.opacity(0.75))
                        }
                        .font(.system(size: 13))
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.08))
                                Capsule().fill(estilo.destaque).frame(width: g.size.width * min(1, app.wh / maior))
                            }
                        }
                        .frame(height: 3)
                    }
                }
                .padding(.vertical, ampliado ? 4 : 3)
            }
            if ampliado {
                Text("Estimativa a partir do uso de CPU de cada app, repartida pela potência medida da bateria. Não é uma medição direta.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: ampliado ? 640 : .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.cartao))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(estilo.bordaCartao, lineWidth: 1))
    }

    private func corDoApp(_ nome: String) -> Color {
        switch nome {
        case "Tela e sistema": return Color(hex: "#D9D4CA")
        case "Claude": return Color(hex: "#E8A07C")
        case "Google Chrome": return Color(hex: "#9CC3F5")
        case "Microsoft Teams": return Color(hex: "#A9A6F2")
        case "Xcode": return Color(hex: "#8FD3F0")
        case "Outros": return Color(hex: "#8C8577")
        default:
            let paleta = ["#F2B5C4", "#B8E0A8", "#F5D68A", "#A8D8E8", "#D4B8F0", "#F0C0A0"]
            let soma = nome.unicodeScalars.reduce(0) { ($0 &+ Int($1.value)) % 997 }
            return Color(hex: paleta[soma % paleta.count])
        }
    }

    // MARK: Saúde

    private func cartaoSaude(ampliado: Bool) -> some View {
        let d = situacao?.detalhes
        let leitura = situacao?.leitura
        let saude = situacao?.saudePercentual.map { min(100, $0) }
        func mah(_ v: Int?) -> String {
            guard let v, v > 0 else { return "–" }
            return v.formatted(.number.locale(Locale(identifier: "pt_BR"))) + " mAh"
        }
        let linhas: [(String, String)] = [
            ("Capacidade agora", mah(leitura?.capacidadeMah)),
            ("Capacidade de fábrica", mah(d?.capacidadeFabricaMah)),
            ("Ciclos", d?.ciclos.map { "\($0) de 1.000" } ?? "–"),
            ("Temperatura agora", d?.temperaturaC.map { "\(Int($0.rounded())) °C" } ?? "–"),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            RotuloSecao("Saúde da bateria")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(saude.map { "\(Int($0.rounded()))%" } ?? "–")
                    .font(.system(size: ampliado ? 48 : 30, weight: .bold))
                    .foregroundStyle(estilo.destaqueTopo)
                Text(saude.map { $0 >= 80 ? "Normal" : "Reduzida" } ?? "sem dados")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            ForEach(linhas.indices, id: \.self) { i in
                HStack {
                    Text(linhas[i].0).foregroundStyle(Color.primary.opacity(0.65))
                    Spacer()
                    Text(linhas[i].1)
                }
                .font(.system(size: ampliado ? 15 : 13)).monospacedDigit()
                .padding(.vertical, ampliado ? 3 : 0)
            }
            if ampliado {
                Text("A capacidade atual é comparada com a de fábrica. Abaixo de 80%, o sistema considera a bateria reduzida.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: ampliado ? 460 : .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.cartao))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(estilo.bordaCartao, lineWidth: 1))
    }

    // MARK: Alertas

    private var cartaoAlertas: some View {
        let a = Ajustes.compartilhado
        let linhas: [(String, Aviso)] = [
            ("Consumo acima de \(Formato.numero(a.avisoConsumoAcima.limite, casas: 0)) %/h", a.avisoConsumoAcima),
            ("Bateria abaixo de \(Formato.numero(a.avisoBateriaAbaixo.limite, casas: 0))%", a.avisoBateriaAbaixo),
            ("Carregou até \(Formato.numero(a.avisoCarregouAte.limite, casas: 0))%", a.avisoCarregouAte),
            ("Carregador fraco, abaixo de \(Formato.numero(a.avisoCarregadorFraco.limite, casas: 0)) W", a.avisoCarregadorFraco),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            RotuloSecao("Avisos")
            ForEach(linhas.indices, id: \.self) { i in
                HStack(spacing: 10) {
                    Image(systemName: linhas[i].1.ligado ? "bell.fill" : "bell.slash")
                        .font(.system(size: 13))
                        .foregroundStyle(linhas[i].1.ligado ? estilo.destaque : Color.secondary)
                        .frame(width: 18)
                    Text(linhas[i].0).font(.system(size: 14))
                    Spacer()
                    Text(linhas[i].1.ligado ? "Ligado" : "Desligado")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(linhas[i].1.ligado ? estilo.primeiroPlanoSelecionado : Color.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(FundoSelecionavel(selecionado: linhas[i].1.ligado, capsula: true))
                }
                .padding(.vertical, 3)
            }
            Text("O consumo vira \"alto\" acima de \(Formato.numero(a.limiteAlto, casas: 0)) %/h. Para mudar os limites, abra Preferências.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: 640, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.cartao))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(estilo.bordaCartao, lineWidth: 1))
    }

    // MARK: Exportar CSV

    private var botaoExportar: some View {
        Button(action: exportarCSV) {
            Text("Exportar CSV do período")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(estilo.destaqueTopo)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(estilo.destaque.opacity(0.5), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(paraFoto)
    }

    private var nomeDoArquivo: String {
        switch periodo {
        case .hoje: return "consumo-bateria-hoje.csv"
        case .seteDias: return "consumo-bateria-7-dias.csv"
        case .trintaDias: return "consumo-bateria-30-dias.csv"
        }
    }

    private func exportarCSV() {
        guard !paraFoto else { return }
        let painel = NSSavePanel()
        painel.nameFieldStringValue = nomeDoArquivo
        painel.allowedContentTypes = [.commaSeparatedText]
        painel.canCreateDirectories = true
        guard painel.runModal() == .OK, let url = painel.url else { return }
        do {
            try historico.csv(periodo).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alerta = NSAlert(error: error)
            alerta.runModal()
        }
    }
}
