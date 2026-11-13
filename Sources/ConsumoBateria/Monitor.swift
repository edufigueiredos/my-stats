import Foundation
import Observation
import ServiceManagement

struct Amostra: Identifiable, Sendable, Codable {
    var id: Date { data }
    var data: Date
    var ritmo: Double   // %/h instantâneo
    var naTomada: Bool
}

@MainActor
@Observable
final class Monitor {
    /// Janela da média móvel que vai na barra.
    static let janelaMedia: TimeInterval = 10 * 60
    /// Quanto do histórico fica para o gráfico.
    static let janelaGrafico: TimeInterval = 60 * 60
    /// Intervalo entre leituras. Ler o IORegistry é barato; o timer tem folga para o sistema agrupar.
    static let intervalo: TimeInterval = 5

    private(set) var atual: LeituraBateria?
    private(set) var amostras: [Amostra] = []
    /// Início do estado atual (tomada ligada/desligada), para a média não misturar carga e descarga.
    private(set) var inicioEstado = Date()
    var abrirAoIniciar: Bool = SMAppService.mainApp.status == .enabled

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var aviso: AvisoEnergia?
    @ObservationIgnored private var naoSalvas = 0

    /// Histórico salvo, para o gráfico sobreviver a reinícios do app.
    static let arquivo: URL = {
        let pasta = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ConsumoBateria", isDirectory: true)
        try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        return pasta.appendingPathComponent("amostras.json")
    }()

    init(vivo: Bool = true) {
        carregar()
        atualizar()
        guard vivo else { return }
        let t = Timer(timeInterval: Self.intervalo, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.atualizar() }
        }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        timer = t
        aviso = AvisoEnergia { [weak self] in
            MainActor.assumeIsolated { self?.atualizar() }
        }
    }

    func atualizar() {
        guard let leitura = LeitorBateria.ler() else { return }
        let estadoAnterior = atual?.naTomada ?? amostras.last?.naTomada
        if estadoAnterior != leitura.naTomada {
            inicioEstado = leitura.data
        }
        atual = leitura
        // O aviso do sistema pode chegar colado no timer; evita amostras repetidas.
        if let ultima = amostras.last, leitura.data.timeIntervalSince(ultima.data) < 1 { return }
        amostras.append(Amostra(data: leitura.data, ritmo: leitura.ritmoInstantaneo, naTomada: leitura.naTomada))
        let corte = leitura.data.addingTimeInterval(-Self.janelaGrafico)
        if let i = amostras.firstIndex(where: { $0.data >= corte }), i > 0 {
            amostras.removeFirst(i)
        }
        naoSalvas += 1
        if naoSalvas >= 12 { salvar() }   // ~1 gravação por minuto
    }

    func salvar() {
        naoSalvas = 0
        if let dados = try? JSONEncoder().encode(amostras) {
            try? dados.write(to: Self.arquivo, options: .atomic)
        }
    }

    private func carregar() {
        guard let dados = try? Data(contentsOf: Self.arquivo),
              let lidas = try? JSONDecoder().decode([Amostra].self, from: dados) else { return }
        let corte = Date().addingTimeInterval(-Self.janelaGrafico)
        amostras = lidas.filter { $0.data >= corte }
        // A média continua de onde parou, desde que o estado da tomada não tenha mudado.
        if let ultimo = amostras.last?.naTomada {
            let inicio = amostras.reversed().prefix { $0.naTomada == ultimo }.last?.data
            inicioEstado = inicio ?? Date()
        }
    }

    /// Média do ritmo nos últimos 10 min (ou desde que a tomada mudou), ponderada pelo tempo.
    var ritmoMedio: Double? {
        guard let atual else { return nil }
        let inicio = max(atual.data.addingTimeInterval(-Self.janelaMedia), inicioEstado)
        let janela = amostras.filter { $0.data >= inicio }
        guard janela.count >= 2, let primeira = janela.first, let ultima = janela.last else {
            return janela.first?.ritmo
        }
        var soma = 0.0
        for (a, b) in zip(janela, janela.dropFirst()) {
            soma += (a.ritmo + b.ritmo) / 2 * b.data.timeIntervalSince(a.data)
        }
        let total = ultima.data.timeIntervalSince(primeira.data)
        return total > 0 ? soma / total : ultima.ritmo
    }

    /// Minutos de dados que entram na média agora.
    var minutosNaMedia: Double {
        guard let atual, let primeira = amostras.first(where: {
            $0.data >= max(atual.data.addingTimeInterval(-Self.janelaMedia), inicioEstado)
        }) else { return 0 }
        return atual.data.timeIntervalSince(primeira.data) / 60
    }

    /// Estimativa própria pelo ritmo médio: até vazia (descarregando) ou até cheia (carregando).
    var minutosEstimados: Double? {
        guard let atual, let ritmo = ritmoMedio, abs(ritmo) > 0.05, atual.capacidadeMah > 0 else { return nil }
        let carga = Double(atual.cargaMah) / Double(atual.capacidadeMah) * 100
        let falta = ritmo < 0 ? carga : 100 - carga
        return falta / abs(ritmo) * 60
    }

    func alternarAbrirAoIniciar(_ ligar: Bool) {
        do {
            if ligar { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("ConsumoBateria: abrir ao iniciar falhou: \(error)")
        }
        abrirAoIniciar = SMAppService.mainApp.status == .enabled
    }
}

enum Formato {
    private static let br = Locale(identifier: "pt_BR")

    static func numero(_ v: Double, casas: Int = 1) -> String {
        v.formatted(.number.precision(.fractionLength(casas)).locale(br))
    }

    /// "−8,3 %/h", "+12,0 %/h" ou "0,0 %/h".
    static func ritmo(_ v: Double?) -> String {
        guard let v else { return "– %/h" }
        let arred = (v * 10).rounded() / 10
        let sinal = arred < 0 ? "−" : (arred > 0 ? "+" : "")
        return "\(sinal)\(numero(abs(arred))) %/h"
    }

    static func duracao(minutos: Double?) -> String {
        guard let minutos, minutos.isFinite, minutos >= 0 else { return "–" }
        let m = Int(minutos.rounded())
        return String(format: "%d:%02d", m / 60, m % 60)
    }
}
