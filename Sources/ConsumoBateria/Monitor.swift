import Foundation
import Observation
import ServiceManagement

/// Amostra de 5 s, guardada só em memória para a média móvel (até 1 h).
struct Amostra: Identifiable, Sendable, Codable {
    var id: Date { data }
    var data: Date
    var ritmo: Double   // %/h instantâneo
    var naTomada: Bool
}

@MainActor
@Observable
final class Monitor {
    /// Janela da média móvel que vai na barra (preferência; padrão 15 min). Zero = valor instantâneo.
    var janelaMedia: TimeInterval { Ajustes.compartilhado.mediaRitmo.segundos }
    /// Quanto das amostras de 5 s fica em memória (a maior média é de 1 h).
    static let janelaAmostras: TimeInterval = 60 * 60
    /// Intervalo entre leituras. Ler o IORegistry é barato; o timer tem folga para o sistema agrupar.
    static let intervalo: TimeInterval = 5
    /// De quanto em quanto tempo o consumo por app é medido (varrer todos os processos custa mais que a bateria).
    static let intervaloApps: TimeInterval = 30

    private(set) var atual: LeituraBateria?
    private(set) var amostras: [Amostra] = []
    private(set) var detalhes = DetalhesEnergia.vazio
    private(set) var apps: [ConsumoApp] = []
    /// Últimas 24 h do histórico, renovadas a cada minuto (o minuto corrente entra em `situacao`).
    private(set) var serie: [PontoMinuto] = []
    /// Início do estado atual (tomada ligada/desligada), para a média não misturar carga e descarga.
    private(set) var inicioEstado = Date()
    var abrirAoIniciar: Bool = SMAppService.mainApp.status == .enabled

    @ObservationIgnored let historico: Historico
    @ObservationIgnored private let medidorApps = MedidorApps()
    @ObservationIgnored private let avisos = Avisos()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var aviso: AvisoEnergia?
    @ObservationIgnored private var ultimaMedicaoApps: Date?
    @ObservationIgnored private var ultimaSerie: Date?

    /// Arquivo da versão antiga (1 h de amostras). Hoje só é lido uma vez, para a média continuar, e apagado.
    private static let arquivoAntigo: URL = {
        let pasta = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ConsumoBateria", isDirectory: true)
        return pasta.appendingPathComponent("amostras.json")
    }()

    init(vivo: Bool = true) {
        historico = Historico(dias: Ajustes.compartilhado.diasHistorico)
        migrarAmostrasAntigas()
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
        let ajustes = Ajustes.compartilhado
        let estadoAnterior = atual?.naTomada ?? amostras.last?.naTomada
        if estadoAnterior != leitura.naTomada {
            inicioEstado = leitura.data
        }
        atual = leitura
        detalhes = LeitorEnergia.ler()
        if historico.diasGuardados != ajustes.diasHistorico { historico.diasGuardados = ajustes.diasHistorico }

        // O aviso do sistema pode chegar colado no timer; evita amostras repetidas.
        let repetida = amostras.last.map { leitura.data.timeIntervalSince($0.data) < 1 } ?? false
        if !repetida {
            amostras.append(Amostra(data: leitura.data, ritmo: leitura.ritmoInstantaneo, naTomada: leitura.naTomada))
            let corte = leitura.data.addingTimeInterval(-Self.janelaAmostras)
            if let i = amostras.firstIndex(where: { $0.data >= corte }), i > 0 {
                amostras.removeFirst(i)
            }
            historico.registrar(PontoMinuto(
                data: leitura.data, percentual: Double(leitura.percentual), ritmo: leitura.ritmoInstantaneo,
                watts: leitura.watts, naTomada: leitura.naTomada, carregando: leitura.carregando))
        }
        medirApps(leitura)
        renovarSerie(leitura.data)
        if let s = situacao { avisos.avaliar(s, ajustes: ajustes) }
    }

    func salvar() {
        historico.salvar()
    }

    // MARK: Situação

    /// Tudo o que a barra, o painel e a janela de detalhes desenham agora; nil sem bateria.
    var situacao: Situacao? {
        guard let atual else { return nil }
        let ritmo = ritmoMedio
        let estado = Situacao.estado(de: atual, ritmo: ritmo, limiteAlto: Ajustes.compartilhado.limiteAlto)
        var pontos = serie
        let agora = PontoMinuto(
            data: atual.data, percentual: Double(atual.percentual), ritmo: atual.ritmoInstantaneo,
            watts: atual.watts, naTomada: atual.naTomada, carregando: atual.carregando)
        if let ultimo = pontos.last, ultimo.data >= agora.data { pontos.removeLast() }
        pontos.append(agora)
        return Situacao(
            leitura: atual, estado: estado, ritmoMedio: ritmo, ritmoAgora: atual.ritmoInstantaneo,
            ritmoUltimaHora: ritmoUltimaHora, minutosAteFim: minutosEstimados, minutosAte80: minutosAte80,
            detalhes: detalhes, apps: apps, serie: pontos)
    }

    /// Carregando abaixo de 80%: minutos até chegar lá, pelo ritmo médio.
    var minutosAte80: Double? {
        guard let atual, atual.carregando, let ritmo = ritmoMedio, ritmo > 0.05, atual.capacidadeMah > 0 else { return nil }
        let carga = Double(atual.cargaMah) / Double(atual.capacidadeMah) * 100
        guard carga < 80 else { return nil }
        return (80 - carga) / ritmo * 60
    }

    // MARK: Apps e série

    private func medirApps(_ leitura: LeituraBateria) {
        let agora = leitura.data
        if let ultima = ultimaMedicaoApps, agora.timeIntervalSince(ultima) < Self.intervaloApps { return }
        let intervalo = ultimaMedicaoApps.map { agora.timeIntervalSince($0) }
        ultimaMedicaoApps = agora
        let naBateria = !leitura.naTomada
        // Na tomada reparte só o que fica com o Mac: a entrada do sistema inclui o que vai para a bateria.
        var watts = 0.0
        if naBateria {
            watts = abs(leitura.watts)
        } else if let entrada = detalhes.entradaSistemaW {
            watts = max(0, entrada - (leitura.carregando ? max(leitura.watts, 0) : 0))
        }
        guard watts > 0 else { apps = []; return }
        let medidos = medidorApps.medir(wattsSistema: watts)
        apps = medidos
        if let intervalo, !medidos.isEmpty { historico.registrarApps(medidos, segundos: intervalo) }
    }

    private func renovarSerie(_ agora: Date) {
        if let ultima = ultimaSerie, agora.timeIntervalSince(ultima) < 55, !serie.isEmpty { return }
        ultimaSerie = agora
        serie = historico.pontos(de: agora.addingTimeInterval(-24 * 3600), ate: agora)
    }

    // MARK: Migração

    /// A versão antiga gravava 1 h de amostras em amostras.json. Lê uma vez para a média continuar e apaga.
    private func migrarAmostrasAntigas() {
        let arquivo = Self.arquivoAntigo
        guard FileManager.default.fileExists(atPath: arquivo.path) else { return }
        defer { try? FileManager.default.removeItem(at: arquivo) }
        guard let dados = try? Data(contentsOf: arquivo),
              let lidas = try? JSONDecoder().decode([Amostra].self, from: dados) else { return }
        let corte = Date().addingTimeInterval(-Self.janelaAmostras)
        amostras = lidas.filter { $0.data >= corte }
        // A média continua de onde parou, desde que o estado da tomada não tenha mudado.
        if let ultimo = amostras.last?.naTomada {
            let inicio = amostras.reversed().prefix { $0.naTomada == ultimo }.last?.data
            inicioEstado = inicio ?? Date()
        }
    }

    /// Média do ritmo na janela escolhida (ou desde que a tomada mudou), ponderada pelo tempo.
    /// Com "Agora" devolve o ritmo instantâneo.
    var ritmoMedio: Double? {
        guard let atual else { return nil }
        if janelaMedia <= 0 { return atual.ritmoInstantaneo }
        return mediaPonderada(desde: max(atual.data.addingTimeInterval(-janelaMedia), inicioEstado))
    }

    /// Média da última hora, sem cortar pela tomada.
    var ritmoUltimaHora: Double? {
        guard let atual else { return nil }
        return mediaPonderada(desde: atual.data.addingTimeInterval(-3600))
    }

    private func mediaPonderada(desde inicio: Date) -> Double? {
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
            $0.data >= max(atual.data.addingTimeInterval(-janelaMedia), inicioEstado)
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

    /// Inteiro com separador de milhar pt-BR: "1.000".
    static func inteiro(_ v: Int) -> String { numero(Double(v), casas: 0) }

    /// Número com "−" tipográfico: "−13,3", "+2,0".
    static func comSinal(_ v: Double, casas: Int = 1) -> String {
        let n = numero(abs(v), casas: casas)
        if n == numero(0, casas: casas) { return n }
        return (v < 0 ? "−" : "+") + n
    }

    /// "−8,3 %/h", "+12,0 %/h" ou "0,0 %/h".
    static func ritmo(_ v: Double?) -> String {
        guard let v else { return "– %/h" }
        let arred = (v * 10).rounded() / 10
        let sinal = arred < 0 ? "−" : (arred > 0 ? "+" : "")
        return "\(sinal)\(numero(abs(arred))) %/h"
    }

    /// Ritmo com casas e sentido: "−11,3 %/h", "↓11,3 %/h", "11,3 %/h" (só cor). `unidade: false` tira o " %/h".
    static func ritmo(_ v: Double?, casas: Int, sentido: SentidoRitmo, unidade: Bool = true) -> String {
        let sufixo = unidade ? " %/h" : ""
        guard let v else { return "–" + sufixo }
        let f = pow(10, Double(casas))
        let arred = (v * f).rounded() / f
        let n = numero(abs(arred), casas: casas)
        switch sentido {
        case .sinais: return (arred < 0 ? "−" : (arred > 0 ? "+" : "")) + n + sufixo
        case .setas: return (arred < 0 ? "↓" : (arred > 0 ? "↑" : "")) + n + sufixo
        case .soCor: return n + sufixo
        }
    }

    /// Potência em módulo: "10,7 W".
    static func watts(_ v: Double?, casas: Int = 1) -> String {
        guard let v else { return "– W" }
        return numero(abs(v), casas: casas) + " W"
    }

    /// Hora do dia: "18:25".
    static func horario(_ d: Date) -> String {
        d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(br))
    }

    /// "54%".
    static func percentual(_ v: Double) -> String { "\(Int(v.rounded()))%" }
    static func percentual(_ v: Int) -> String { "\(v)%" }

    static func duracao(minutos: Double?) -> String {
        guard let minutos, minutos.isFinite, minutos >= 0 else { return "–" }
        let m = Int(minutos.rounded())
        return String(format: "%d:%02d", m / 60, m % 60)
    }
}
