import Foundation

// Histórico curto em memória dos módulos (só dos ligados): pontos finos da última 1 h e médias por minuto até 24 h.

enum PeriodoModulo: String, CaseIterable, Identifiable, Sendable {
    case umMin, dezMin, umaHora, vinteQuatroHoras

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .umMin: return "1 min"
        case .dezMin: return "10 min"
        case .umaHora: return "1 h"
        case .vinteQuatroHoras: return "24 h"
        }
    }

    var segundos: TimeInterval {
        switch self {
        case .umMin: return 60
        case .dezMin: return 600
        case .umaHora: return 3_600
        case .vinteQuatroHoras: return 86_400
        }
    }
}

/// Unidades: percentuais em 0...100; bytes/s em disco e rede; ms na latência; °C; W.
/// `memUsada` e `memPressao` são percentuais.
enum MetricaSerie: String, CaseIterable, Sendable {
    case cpuUso, cpuApps, cpuSistema, gpuUso, memUsada, memPressao
    case discoLeitura, discoEscrita, redeBaixa, redeSobe, redeLatencia
    case tempCPU, tempGPU, tempMemoria, tempSSD, tempBateria, tempAr, sistemaW
}

struct PontoSerie: Sendable, Equatable {
    var data: Date
    var valor: Double
}

struct SerieCurta: Sendable, Equatable {
    /// Quanto cada nível guarda.
    static let janelaFina: TimeInterval = 3_600
    static let janelaMinutos: TimeInterval = 86_400

    private(set) var finos: [PontoSerie] = []
    private(set) var minutos: [PontoSerie] = []
    /// Minuto em acúmulo: início, soma e quantidade.
    private var atualInicio: Date?
    private var atualSoma = 0.0
    private var atualQtd = 0

    /// Registra uma leitura; datas devem crescer. Corta o que passou da janela.
    mutating func registrar(_ valor: Double, em data: Date) {
        guard valor.isFinite else { return }
        finos.append(PontoSerie(data: data, valor: valor))
        let corteFino = data.addingTimeInterval(-Self.janelaFina)
        if let primeiroValido = finos.firstIndex(where: { $0.data >= corteFino }), primeiroValido > 0 {
            finos.removeFirst(primeiroValido)
        }

        let inicioMinuto = Date(timeIntervalSinceReferenceDate: (data.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
        if let atualInicio, atualInicio != inicioMinuto { fecharMinuto() }
        if atualInicio == nil { atualInicio = inicioMinuto }
        atualSoma += valor
        atualQtd += 1

        let corteMinutos = data.addingTimeInterval(-Self.janelaMinutos)
        if let primeiroValido = minutos.firstIndex(where: { $0.data >= corteMinutos }), primeiroValido > 0 {
            minutos.removeFirst(primeiroValido)
        }
    }

    private mutating func fecharMinuto() {
        if let inicio = atualInicio, atualQtd > 0 {
            minutos.append(PontoSerie(data: inicio.addingTimeInterval(30), valor: atualSoma / Double(atualQtd)))
        }
        atualInicio = nil; atualSoma = 0; atualQtd = 0
    }

    /// Médias por minuto, com o minuto em andamento no fim.
    private var pontosMinuto: [PontoSerie] {
        guard let inicio = atualInicio, atualQtd > 0 else { return minutos }
        return minutos + [PontoSerie(data: inicio.addingTimeInterval(30), valor: atualSoma / Double(atualQtd))]
    }

    /// Média de cada coluna na janela que termina em `agora`; nil onde não há dado.
    func valores(janela: TimeInterval, colunas: Int, agora: Date) -> [Double?] {
        guard colunas > 0, janela > 0 else { return [] }
        let inicio = agora.addingTimeInterval(-janela)
        let largura = janela / Double(colunas)
        var soma = [Double](repeating: 0, count: colunas)
        var qtd = [Int](repeating: 0, count: colunas)
        let fonte = janela <= Self.janelaFina ? finos : pontosMinuto
        for p in fonte where p.data >= inicio && p.data <= agora {
            let i = min(Int(p.data.timeIntervalSince(inicio) / largura), colunas - 1)
            soma[i] += p.valor
            qtd[i] += 1
        }
        return (0..<colunas).map { qtd[$0] > 0 ? soma[$0] / Double(qtd[$0]) : nil }
    }

    func valores(periodo: PeriodoModulo, colunas: Int, agora: Date) -> [Double?] {
        valores(janela: periodo.segundos, colunas: colunas, agora: agora)
    }

    /// Pontos desde `desde`: os finos onde existem, médias por minuto antes deles.
    private func pontos(desde: Date) -> [PontoSerie] {
        let corte = finos.first?.data ?? .distantFuture
        return pontosMinuto.filter { $0.data >= desde && $0.data < corte } + finos.filter { $0.data >= desde }
    }

    func maximo(desde: Date) -> Double? { pontos(desde: desde).map(\.valor).max() }

    func pico(desde: Date) -> PontoSerie? { pontos(desde: desde).max { $0.valor < $1.valor } }

    /// Os `n` últimos valores finos, para o minigráfico do item da barra.
    func ultimos(_ n: Int) -> [Double] { finos.suffix(max(n, 0)).map(\.valor) }
}

struct SeriesModulos: Sendable, Equatable {
    var series: [MetricaSerie: SerieCurta] = [:]

    mutating func registrar(_ m: MetricaSerie, _ valor: Double, em data: Date) {
        series[m, default: SerieCurta()].registrar(valor, em: data)
    }

    func valores(_ m: MetricaSerie, periodo: PeriodoModulo, colunas: Int, agora: Date) -> [Double?] {
        series[m]?.valores(periodo: periodo, colunas: colunas, agora: agora) ?? Array(repeating: nil, count: max(colunas, 0))
    }

    /// Mesma coisa com janela livre em segundos (a latência do desenho usa 2 min).
    func valores(_ m: MetricaSerie, janela: TimeInterval, colunas: Int, agora: Date) -> [Double?] {
        series[m]?.valores(janela: janela, colunas: colunas, agora: agora) ?? Array(repeating: nil, count: max(colunas, 0))
    }

    func maximo(_ m: MetricaSerie, desde: Date) -> Double? { series[m]?.maximo(desde: desde) }
    func pico(_ m: MetricaSerie, desde: Date) -> PontoSerie? { series[m]?.pico(desde: desde) }
    func ultimos(_ m: MetricaSerie, _ n: Int) -> [Double] { series[m]?.ultimos(n) ?? [] }
}

// MARK: - Exemplo (vetores dos desenhos)

extension SeriesModulos {
    /// Espalha cada vetor pela janela, uma coluna por valor: `valores(...)` devolve a forma do desenho.
    /// `minigrafico` são os 12 valores de Main.dc.html, que ficam no fim da série (`ultimos(12)`); a última coluna
    /// ganha pontos de compensação para a média dela continuar igual ao valor do desenho.
    private static func preencher(_ s: inout SeriesModulos, _ m: MetricaSerie, _ vetor: [Double], janela: TimeInterval,
                                  minigrafico: [Double]? = nil, agora: Date) {
        guard !vetor.isEmpty else { return }
        let n = vetor.count
        let largura = janela / Double(n)
        let inicio = agora.addingTimeInterval(-janela)
        for i in 0..<n {
            let ultima = i == n - 1
            if ultima, let mini = minigrafico, !mini.isEmpty {
                let k = mini.count
                let alvo = vetor[i]
                let compensar = max((Double(2 * k) * alvo - mini.reduce(0, +)) / Double(k), 0)
                let comeco = inicio.addingTimeInterval(Double(i) * largura)
                // Primeira metade da coluna: compensação; segunda: o minigráfico, terminando em `agora`.
                for j in 0..<k {
                    s.registrar(m, compensar, em: comeco.addingTimeInterval(largura / 2 * (Double(j) + 0.5) / Double(k)))
                }
                for j in 0..<k {
                    s.registrar(m, mini[j], em: agora.addingTimeInterval(-largura / 2 * Double(k - 1 - j) / Double(k)))
                }
            } else {
                s.registrar(m, vetor[i], em: inicio.addingTimeInterval((Double(i) + 0.5) * largura))
            }
        }
    }

    /// Rampa suave até `fim`, com ondulação fixa; serve para métricas que o desenho só mostra como número.
    private static func rampa(de: Double, ate fim: Double, pontos: Int = 30) -> [Double] {
        (0..<pontos).map { i in
            let t = Double(i) / Double(pontos - 1)
            return de + (fim - de) * t + 1.2 * sin(Double(i) * 1.7)
        }
    }

    static func exemplo(agora: Date) -> SeriesModulos {
        var s = SeriesModulos()
        let dez: TimeInterval = 600
        let ap: [Double] = [22, 25, 24, 30, 28, 35, 40, 38, 44, 50, 48, 52, 55, 58, 54, 60, 62, 58, 64, 66, 62, 60, 63, 65, 61, 64, 62, 60, 63, 61]
        let si: [Double] = [8, 9, 8, 10, 9, 11, 12, 12, 14, 15, 16, 15, 18, 19, 18, 20, 21, 20, 22, 22, 21, 20, 22, 23, 21, 22, 22, 21, 22, 22]
        let gpu: [Double] = [18, 20, 22, 30, 42, 55, 66, 72, 78, 70, 62, 58, 52, 48, 50, 55, 60, 57, 52, 49, 51, 54, 50, 48, 52, 55, 53, 51, 54, 53]
        let pressao: [Double] = [14, 15, 15, 16, 18, 22, 30, 34, 28, 22, 20, 18, 17, 17, 18, 19, 20, 19, 18, 18, 17, 18, 19, 18, 18, 17, 18, 18, 19, 18]
        let lv: [Double] = [2, 3, 2, 40, 90, 70, 20, 5, 3, 2, 10, 35, 60, 22, 6, 4, 3, 2, 2, 15, 48, 80, 55, 18, 8, 5, 30, 64, 40, 24]
        let ev: [Double] = [1, 1, 2, 10, 20, 8, 3, 1, 1, 1, 4, 30, 50, 12, 3, 2, 1, 1, 1, 6, 14, 22, 9, 4, 2, 1, 6, 12, 9, 5]
        let bv: [Double] = [10, 12, 8, 30, 60, 85, 70, 40, 22, 18, 20, 26, 34, 50, 62, 58, 44, 30, 24, 20, 18, 22, 28, 36, 42, 48, 52, 50, 46, 44]
        let sv: [Double] = [2, 2, 3, 4, 6, 8, 5, 3, 2, 2, 3, 4, 6, 9, 12, 10, 6, 4, 3, 3, 2, 3, 4, 5, 6, 7, 6, 5, 5, 4]
        let ping: [Double] = [7, 6, 6, 8, 6, 5, 6, 7, 6, 6, 9, 6, 5, 6, 84, 22, 8, 6, 6, 7, 6, 5, 6, 6, 7, 6, 6, 8, 6, 5, 6, 7, 6, 6, 5, 6, 7, 6, 6, 6]

        // Minigráficos de Main.dc.html (12 valores por módulo).
        let miniCPU: [Double] = [40, 55, 48, 62, 70, 66, 74, 81, 77, 85, 80, 83]
        let miniGPU: [Double] = [20, 22, 30, 45, 60, 58, 50, 47, 55, 52, 49, 53]
        let miniMem: [Double] = [48, 48, 49, 49, 50, 50, 51, 50, 50, 49, 50, 50]
        let miniDisco: [Double] = [5, 8, 60, 90, 35, 10, 6, 4, 20, 45, 12, 8].map { $0 * 1e6 }
        let miniPing: [Double] = [8, 7, 6, 9, 6, 5, 6, 7, 30, 8, 6, 6]
        let miniTemp: [Double] = [70, 72, 75, 80, 84, 88, 90, 92, 91, 90, 91, 91]

        preencher(&s, .cpuApps, ap, janela: dez, agora: agora)
        preencher(&s, .cpuSistema, si, janela: dez, agora: agora)
        preencher(&s, .cpuUso, zip(ap, si).map { $0 + $1 }, janela: dez, minigrafico: miniCPU, agora: agora)
        preencher(&s, .gpuUso, gpu, janela: dez, minigrafico: miniGPU, agora: agora)
        // Memória usada: o desenho só dá o número (50%); rampa curta de 46 a 50.
        var mem = rampa(de: 46, ate: 50)
        mem[mem.count - 1] = 50
        preencher(&s, .memUsada, mem, janela: dez, minigrafico: miniMem, agora: agora)
        preencher(&s, .memPressao, pressao, janela: 3_600, agora: agora)
        preencher(&s, .discoLeitura, lv.map { $0 * 1e6 }, janela: dez, minigrafico: miniDisco, agora: agora)
        preencher(&s, .discoEscrita, ev.map { $0 * 1e6 }, janela: dez, agora: agora)
        preencher(&s, .redeBaixa, bv.map { $0 * 12.4e6 / 44 }, janela: dez, agora: agora)
        preencher(&s, .redeSobe, sv.map { $0 * 205e3 }, janela: dez, agora: agora)
        preencher(&s, .redeLatencia, ping, janela: 120, minigrafico: miniPing, agora: agora)

        // Temperatura da CPU sobe até 98 e se assenta em 91; as outras ficam perto do valor atual.
        var tempCPU = rampa(de: 62, ate: 93)
        tempCPU[22] = 98
        tempCPU[tempCPU.count - 1] = 91
        preencher(&s, .tempCPU, tempCPU, janela: dez, minigrafico: miniTemp, agora: agora)
        for (m, valor) in [(MetricaSerie.tempGPU, 63.0), (.tempMemoria, 52), (.tempSSD, 45), (.tempBateria, 33), (.tempAr, 41)] {
            var v = rampa(de: valor - 8, ate: valor)
            v[v.count - 1] = valor
            preencher(&s, m, v, janela: dez, agora: agora)
        }
        var watts = rampa(de: 70, ate: 100)
        watts[watts.count - 1] = 100
        preencher(&s, .sistemaW, watts, janela: dez, agora: agora)
        return s
    }
}
