import SwiftUI

// Painel da GPU (docs/desenho/modulos/PainelGPU.dc.html).

struct PainelGPU: View {
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
    private var gpu: LeituraGPU? { leituras.gpu }

    var body: some View {
        MolduraPainelModulo(alturaMaxima: alturaMaxima) {
            CabecalhoModulo(icone: .gpu, titulo: "GPU", subtitulo: subtitulo, corPonto: Paleta.bom,
                            rotuloPreferencias: "Preferências da GPU", aoPreferencias: acoes.preferencias)
            cartaoUso
            BlocosModulo(blocos)
            ChipsPeriodo(selecao: periodo, aoEscolher: { periodo = $0 })
            CartaoGraficoPainel(eixo: rotulosEixoPainel(janela: periodo.segundos, agora: agora)) {
                GraficoColunas(valores: series.valores(.gpuUso, periodo: periodo, colunas: 30, agora: agora),
                               maximo: 100, altura: 90,
                               cor: { _, _ in estilo.destaque }, opacidade: { $0 >= 26 ? 1 : 0.6 })
            }
            motores
            SecaoProcessosPainel(dica: "tempo de GPU", itens: processos)
            CartaoLinhas(linhas)
        } rodape: {
            RodapePainelModulo(modulo: .gpu, acoes: acoes)
        }
    }

    private var subtitulo: String {
        guard let gpu else { return "Sem leitura" }
        let tipo = gpu.telas.contains(where: \.integrada) ? "Integrada" : (gpu.nome ?? "GPU")
        let n = gpu.telas.count
        return n == 0 ? tipo : "\(tipo) · \(n) \(n == 1 ? "tela" : "telas")"
    }

    // MARK: Uso

    private var cartaoUso: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Uso · média de 5 s")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.primary.opacity(0.6))
                NumeroUsoPainel(texto: gpu?.uso.map { Formato.inteiro(Int($0.rounded())) } ?? Formato.semDado,
                                unidade: gpu?.uso == nil ? nil : "%")
                if let pico {
                    Text(pico).font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.62)).monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            AnelCentroPainel(fracao: (leituras.sensores?.gpuC ?? 0) / 110,
                             centro: Formato.temperatura(leituras.sensores?.gpuC, curta: true), sub: "GPU")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(estilo.cartao))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(estilo.bordaCartao, lineWidth: 1))
    }

    /// Pico dos últimos 10 min: "Pico de 78% há 4 min".
    private var pico: String? {
        guard let p = series.pico(.gpuUso, desde: agora.addingTimeInterval(-600)) else { return nil }
        let min = Int((agora.timeIntervalSince(p.data) / 60).rounded())
        return "Pico de \(Formato.percentual(p.valor))" + (min >= 1 ? " há \(min) min" : " agora")
    }

    // MARK: Blocos

    private var blocos: [(rotulo: String, valor: String, sub: String)] {
        let w = leituras.energia?.gpuW
        let mem = gpu?.memoriaEmUsoBytes
        let mhz = leituras.energia?.gpuMHz
        let maxMHz = leituras.energia?.gpuMaxMHz
        // Não há série de potência da GPU: o sub fica "agora".
        var subFreq = Formato.semDado
        if let mhz, let maxMHz, maxMHz > 0 { subFreq = Formato.percentual(mhz / maxMHz * 100) + " do máx." }
        return [
            ("Potência", w.map { Formato.numero($0, casas: 0) + " W" } ?? Formato.semDado, "agora"),
            ("Memória", mem.map { Formato.bytesMemoria($0) } ?? Formato.semDado, "em uso pela GPU"),
            ("Frequência", mhz.map { Formato.numero($0 / 1000, casas: 2) + " GHz" } ?? Formato.semDado, subFreq),
        ]
    }

    // MARK: Motores de vídeo

    @ViewBuilder
    private var motores: some View {
        let itens: [(String, Double)] = [("Codificar vídeo", gpu?.codificarVideo), ("Decodificar vídeo", gpu?.decodificarVideo)]
            .compactMap { r in r.1.map { (r.0, $0) } }
        if !itens.isEmpty {
            VStack(spacing: 14) {
                CabecalhoSecao("Motores de vídeo").padding(.top, 2)
                Cartao {
                    VStack(spacing: 10) {
                        ForEach(itens.indices, id: \.self) { i in
                            VStack(spacing: 5) {
                                HStack {
                                    Text(itens[i].0).foregroundStyle(Color.primary.opacity(0.68))
                                    Spacer(minLength: 8)
                                    Text(Formato.percentual(itens[i].1)).monospacedDigit()
                                }
                                .font(.system(size: 14))
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.08))
                                        RoundedRectangle(cornerRadius: 2).fill(estilo.destaque)
                                            .frame(width: g.size.width * CGFloat(min(max(itens[i].1, 0), 100) / 100))
                                    }
                                }
                                .frame(height: 4)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Processos e linhas

    private var processos: [(nome: String, valor: String, fracao: Double?)] {
        (leituras.processos.gpu ?? []).prefix(4).map { ($0.nome, Formato.percentual($0.valor), nil) }
    }

    private var linhas: [(String, String)] {
        let telas = (gpu?.telas ?? []).map { t in t.hz.map { "\(t.nome) \($0) Hz" } ?? t.nome }
        return [
            ("Núcleos gráficos", gpu?.nucleos.map { Formato.inteiro($0) } ?? Formato.semDado),
            ("Telas", telas.isEmpty ? Formato.semDado : telas.joined(separator: " · ")),
            ("Temperatura", Formato.temperatura(leituras.sensores?.gpuC, curta: false)),
        ]
    }
}
