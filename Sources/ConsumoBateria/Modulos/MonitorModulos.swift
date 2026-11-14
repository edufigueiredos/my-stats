import Foundation
import Observation
import Darwin

/// Lê os módulos do sistema num timer próprio, só dos que estão ligados ou com painel aberto, e guarda a leitura
/// atual e as séries curtas. Sem módulo ligado nem painel aberto não há timer.
@MainActor
@Observable
final class MonitorModulos {
    private(set) var leituras: LeiturasModulos
    private(set) var series = SeriesModulos()

    /// Painéis de módulo abertos no popover (postos pelo controlador).
    var paineisAbertos: Set<Modulo> = [] {
        didSet { mudouAbertos(antes: oldValue, agora: paineisAbertos, anterior: oldValue == paineisAbertos) }
    }
    /// Visão geral aberta: lê todos os módulos.
    var geralAberto = false {
        didSet {
            guard oldValue != geralAberto else { return }
            reavaliar()
            if geralAberto { atualizar() }
        }
    }

    @ObservationIgnored private let ajustes: AjustesModulos
    @ObservationIgnored private let vivo: Bool
    @ObservationIgnored private let energiaBateria: @MainActor () -> (entradaW: Double?, carregadorW: Double?)
    @ObservationIgnored private let avisos = AvisosModulos()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var intervaloDoTimer: TimeInterval = 0
    @ObservationIgnored private let ligadoDesde: Date?

    @ObservationIgnored private lazy var leitorCPU = LeitorCPU()
    @ObservationIgnored private lazy var leitorGPU = LeitorGPU()
    @ObservationIgnored private lazy var leitorMemoria = LeitorMemoria()
    @ObservationIgnored private lazy var leitorDisco = LeitorDisco()
    @ObservationIgnored private lazy var leitorRede = LeitorRede()
    @ObservationIgnored private lazy var leitorSensores = LeitorSensores()
    @ObservationIgnored private lazy var leitorEnergia = LeitorEnergiaSoC()
    @ObservationIgnored private lazy var leitorProcessos = LeitorProcessos()

    init(ajustes: AjustesModulos = .compartilhado, vivo: Bool = true,
         energiaBateria: @escaping @MainActor () -> (entradaW: Double?, carregadorW: Double?)) {
        self.ajustes = ajustes
        self.vivo = vivo
        self.energiaBateria = energiaBateria
        let desde = Self.inicioDoSistema()
        ligadoDesde = desde
        leituras = LeiturasModulos(data: Date(), ligadoDesde: desde)
        reavaliar()
        if timer != nil { atualizar() }
    }

    /// Instante da última inicialização do Mac (sysctl kern.boottime).
    private static func inicioDoSistema() -> Date? {
        var tv = timeval()
        var tamanho = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &tv, &tamanho, nil, 0) == 0, tv.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec))
    }

    // MARK: Timer

    private var modulosAtivos: Set<Modulo> {
        if geralAberto { return Set(Modulo.allCases) }
        return Set(ajustes.ligados).union(paineisAbertos)
    }

    /// Cria, recria (o intervalo mudou) ou para o timer conforme haja o que ler.
    func reavaliar() {
        guard vivo else { return }
        guard !modulosAtivos.isEmpty else {
            timer?.invalidate()
            timer = nil
            intervaloDoTimer = 0
            if leituras.cpu != nil || leituras.gpu != nil || leituras.memoria != nil || leituras.disco != nil
                || leituras.rede != nil || leituras.sensores != nil || leituras.energia != nil {
                leituras = LeiturasModulos(data: Date(), ligadoDesde: ligadoDesde)
            }
            return
        }
        let intervalo = ajustes.intervalo.rawValue
        if timer != nil, intervaloDoTimer == intervalo { return }
        timer?.invalidate()
        let t = Timer(timeInterval: intervalo, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.atualizar() }
        }
        t.tolerance = intervalo * 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
        intervaloDoTimer = intervalo
    }

    private func mudouAbertos(antes: Set<Modulo>, agora: Set<Modulo>, anterior igual: Bool) {
        guard !igual else { return }
        reavaliar()
        if !agora.isSubset(of: antes) { atualizar() }
    }

    // MARK: Leitura

    /// Lê só o necessário e registra as séries. Módulo desligado e sem painel fica com a leitura nil.
    func atualizar() {
        let ativos = modulosAtivos
        let agora = Date()
        var l = LeiturasModulos(data: agora, ligadoDesde: ligadoDesde)
        guard !ativos.isEmpty else {
            leituras = l
            return
        }

        if ativos.contains(.cpu) { l.cpu = leitorCPU.ler() }
        if ativos.contains(.gpu) { l.gpu = leitorGPU.ler() }
        if ativos.contains(.memoria) { l.memoria = leitorMemoria.ler() }
        if ativos.contains(.disco) { l.disco = leitorDisco.ler() }
        if ativos.contains(.rede) {
            l.rede = leitorRede.ler()
            leitorRede.pingarSePreciso()
        }

        let painelRede = paineisAbertos.contains(.rede) && !geralAberto
        let painelUsaSensores = !paineisAbertos.isDisjoint(with: [.cpu, .gpu, .sensores, .disco])
        let precisaSensores = ajustes.precisaSensores || avisoDeTemperaturaLigado
            || geralAberto || painelUsaSensores
        if precisaSensores {
            let bat = energiaBateria()
            l.sensores = leitorSensores.ler(entradaSistemaW: bat.entradaW, carregadorW: bat.carregadorW)
        }
        // IOReport também dá o uso da GPU: o "Device Utilization %" do registro é instantâneo e quase sempre 0.
        if precisaSensores || ativos.contains(.gpu) { l.energia = leitorEnergia.ler() }
        if let a = l.energia?.gpuAtivo, l.gpu != nil { l.gpu?.uso = a }

        // "Quem mais usa": só enquanto o painel está aberto.
        let abertoCPU = geralAberto || paineisAbertos.contains(.cpu)
        let abertoMem = geralAberto || paineisAbertos.contains(.memoria)
        let abertoDisco = paineisAbertos.contains(.disco)
        var p = ProcessosModulos()
        if abertoCPU || abertoMem || abertoDisco {
            p = leitorProcessos.medir(cpu: abertoCPU, memoria: abertoMem, disco: abertoDisco)
        }
        if paineisAbertos.contains(.gpu) { p.gpu = leitorProcessos.medirGPU() }
        if painelRede {
            leitorRede.medirProcessosSePreciso()
            p.rede = leitorRede.processos
        }
        l.processos = p

        leituras = l
        registrarSeries(l, em: agora)
        avisos.avaliar(l, ajustes: ajustes)
    }

    /// Grava o total de rede do dia ao encerrar o app.
    func gravarRedeAgora() { leitorRede.gravarAgora() }

    private var avisoDeTemperaturaLigado: Bool {
        ajustes.modulos.contains { a in
            a.ligado && a.avisos.contains { $0.ligado && $0.tipo == .temperaturaAcima }
        }
    }

    private func registrarSeries(_ l: LeiturasModulos, em data: Date) {
        var s = series
        if let c = l.cpu {
            s.registrar(.cpuUso, c.uso, em: data)
            s.registrar(.cpuApps, c.usuario, em: data)
            s.registrar(.cpuSistema, c.sistema, em: data)
        }
        if let g = l.gpu?.uso { s.registrar(.gpuUso, g, em: data) }
        if let m = l.memoria {
            s.registrar(.memUsada, m.usadaPercentual, em: data)
            if let pr = m.pressaoPercentual { s.registrar(.memPressao, pr, em: data) }
        }
        if let d = l.disco {
            s.registrar(.discoLeitura, d.leituraBps, em: data)
            s.registrar(.discoEscrita, d.escritaBps, em: data)
        }
        if let r = l.rede {
            s.registrar(.redeBaixa, r.baixandoBps, em: data)
            s.registrar(.redeSobe, r.enviandoBps, em: data)
            if let ms = r.latenciaMs { s.registrar(.redeLatencia, ms, em: data) }
        }
        if let t = l.sensores {
            let pares: [(MetricaSerie, Double?)] = [
                (.tempCPU, t.cpuC), (.tempGPU, t.gpuC), (.tempMemoria, t.memoriaC), (.tempSSD, t.ssdC),
                (.tempBateria, t.bateriaC), (.tempAr, t.arC), (.sistemaW, t.sistemaW)]
            for (m, v) in pares { if let v { s.registrar(m, v, em: data) } }
        }
        series = s
    }
}
