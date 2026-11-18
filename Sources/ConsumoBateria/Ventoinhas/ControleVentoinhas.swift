import AppKit
import Observation
import ServiceManagement
import VentoinhasXPC

/// Situação do ajudante root que muda a rotação (Sources/MyStatsVentoinhas).
enum EstadoAjudante: Equatable, Sendable {
    /// Ainda não foi preciso (modo Automático desde sempre).
    case naoUsado
    /// Registrado, esperando o usuário permitir em Ajustes do Sistema › Geral › Itens de início.
    case precisaAprovar
    case pronto
    case indisponivel(String)
}

/// Controle das ventoinhas: lê a temperatura, calcula o alvo do modo escolhido e manda ao ajudante a cada 2 s.
/// O alvo vale 8 s no ajudante: se o app parar de renovar, as ventoinhas voltam ao macOS sozinhas.
@MainActor
@Observable
final class ControleVentoinhas {
    static let compartilhado = ControleVentoinhas()

    nonisolated static let chave = "ventoinhas"
    private static let intervalo: TimeInterval = 2
    private static let validade: Double = 8

    var ajustes: AjustesVentoinhas {
        didSet {
            guard ajustes != oldValue else { return }
            gravar()
            guard vivo else { return }
            // Trocar de modo vale na hora; mexer no % ou na curva espera o arraste parar um pouco.
            if ajustes.modo != oldValue.modo || ajustes.modo == .automatico { aplicar() } else { agendarPasso() }
        }
    }
    private(set) var estado: EstadoAjudante = .naoUsado
    /// Temperatura que manda agora (segundo a referência escolhida).
    private(set) var temperatura: Double?
    /// % que o app está pedindo agora, por ventoinha (vazio no Automático).
    private(set) var pedido: [Double] = []
    /// Passou do limite de segurança: tudo no máximo.
    private(set) var noLimite = false
    private(set) var erro: String?

    @ObservationIgnored private let persistir: Bool
    @ObservationIgnored private let vivo: Bool
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var conexao: NSXPCConnection?
    @ObservationIgnored private var versaoConferida = false
    /// O app mandou algum alvo desde que abriu (para saber se precisa devolver ao macOS ao voltar ao Automático).
    @ObservationIgnored private var controlou = false
    /// A leitura dos sensores (~340 no M5, dezenas de ms) roda nesta fila, para não travar cliques e arrastes.
    @ObservationIgnored private let filaLeitura = DispatchQueue(label: "ventoinhas.leitura", qos: .utility)
    @ObservationIgnored private let leitor = LeitorSensores()
    @ObservationIgnored private var lendo = false
    @ObservationIgnored private var passoAgendado: Task<Void, Never>?

    init(persistir: Bool = true, vivo: Bool = true, ajustes inicial: AjustesVentoinhas? = nil) {
        self.persistir = persistir
        self.vivo = vivo
        var a = inicial ?? AjustesVentoinhas()
        if persistir, let dados = UserDefaults.standard.data(forKey: Self.chave),
           let g = try? JSONDecoder().decode(AjustesVentoinhas.self, from: dados) {
            a = g
        }
        ajustes = a
    }

    @ObservationIgnored private var gravacaoAgendada: Task<Void, Never>?

    /// Grava meio segundo depois da última mudança (arrastar a barra do Manual muda o ajuste muitas vezes por segundo).
    private func gravar() {
        guard persistir else { return }
        gravacaoAgendada?.cancel()
        gravacaoAgendada = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, let dados = try? JSONEncoder().encode(self.ajustes) else { return }
            UserDefaults.standard.set(dados, forKey: Self.chave)
        }
    }

    // MARK: Ciclo

    /// Ao abrir o app: reaplica o modo salvo, ou volta ao Automático se o usuário não quer reaplicar.
    func iniciar() {
        guard vivo else { return }
        if !ajustes.reaplicar, ajustes.modo != .automatico { ajustes.modo = .automatico }
        aplicar()
    }

    /// Ao fechar o app: devolve as ventoinhas ao macOS (o ajudante também faz isso quando a conexão cai).
    func encerrar() {
        if persistir, let dados = try? JSONEncoder().encode(ajustes) { UserDefaults.standard.set(dados, forKey: Self.chave) }
        timer?.invalidate()
        timer = nil
        guard controlou, let c = conexao else { return }
        let espera = DispatchSemaphore(value: 0)
        let proxy = c.synchronousRemoteObjectProxyWithErrorHandler { _ in espera.signal() } as? ProtocoloVentoinhas
        proxy?.automatico { _ in espera.signal() }
        _ = espera.wait(timeout: .now() + 0.8)
        c.invalidate()
    }

    /// Liga ou desliga o laço conforme o modo.
    private func aplicar() {
        if ajustes.modo == .automatico {
            timer?.invalidate()
            timer = nil
            pedido = []
            noLimite = false
            // Também ao abrir o app: se as ventoinhas ficaram presas em manual (o app caiu, outro programa), soltam aqui.
            if controlou || servico.status == .enabled { mandarAutomatico() }
            return
        }
        prepararAjudante()
        if timer == nil {
            let t = Timer(timeInterval: Self.intervalo, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.passo() }
            }
            t.tolerance = 0.3
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        passo()
    }

    private func agendarPasso() {
        passoAgendado?.cancel()
        passoAgendado = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.passo()
        }
    }

    private func passo() {
        guard ajustes.modo != .automatico else { return }
        if estado != .pronto {
            prepararAjudante()
            guard estado == .pronto else { return }
        } else {
            conectarSePreciso()
        }
        guard !lendo else { return }
        lendo = true
        let leitor = self.leitor
        filaLeitura.async { [weak self] in
            let s = leitor.ler(entradaSistemaW: nil, carregadorW: nil)
            Task { @MainActor in
                self?.lendo = false
                self?.seguir(com: s)
            }
        }
    }

    private func seguir(com s: LeituraSensores?) {
        guard ajustes.modo != .automatico else { return }
        let fans = s?.ventoinhas ?? []
        let temp: Double?
        switch ajustes.referencia {
        case .cpu: temp = s?.cpuC
        case .gpu: temp = s?.gpuC
        case .maisQuente: temp = [s?.cpuC, s?.gpuC].compactMap { $0 }.max()
        }
        temperatura = temp
        guard !fans.isEmpty else {
            erro = "Não encontrei as ventoinhas deste Mac."
            return
        }
        // Sem temperatura não há como seguir a curva nem o limite: devolve ao macOS.
        guard let temp else {
            mandarAutomatico()
            return
        }
        noLimite = temp >= ajustes.limite
        var pcts: [Double] = []
        var rpms: [Double] = []
        for (i, v) in fans.enumerated() {
            let maximo = v.maximoRpm ?? 0, minimo = v.minimoRpm ?? 0
            var pct: Double
            switch ajustes.modo {
            case .manual:
                pct = ajustes.separadas ? (i < ajustes.manualPorVentoinha.count ? ajustes.manualPorVentoinha[i] : ajustes.manualPct)
                                        : ajustes.manualPct
            case .curva, .automatico:
                pct = AjustesVentoinhas.pct(curva: ajustes.curva, temp: temp)
            }
            if noLimite { pct = 100 }
            pcts.append(pct)
            if ajustes.modo == .curva, pct < 0.5 {
                rpms.append(Ventoinhas.automatico)   // 0% na curva: o macOS decide (e para a ventoinha com o Mac frio)
            } else if pct < 0.5 {
                rpms.append(0)
            } else {
                rpms.append(maximo > 0 ? max(minimo, pct / 100 * maximo) : Ventoinhas.automatico)
            }
        }
        pedido = pcts
        mandar(rpms)
    }

    // MARK: Ajudante

    private var servico: SMAppService { SMAppService.daemon(plistName: Ventoinhas.plist) }

    /// Registra o ajudante (a primeira vez pede a aprovação do usuário) e conecta quando ele está liberado.
    private func prepararAjudante() {
        switch servico.status {
        case .enabled:
            if estado != .pronto { estado = .pronto }
            conectarSePreciso()
        case .requiresApproval:
            estado = .precisaAprovar
        case .notRegistered, .notFound:
            do {
                try servico.register()
                estado = servico.status == .enabled ? .pronto : .precisaAprovar
                if estado == .pronto { conectarSePreciso() }
            } catch {
                let e = error as NSError
                // Registrado mas sem aprovação ainda: o register() reclama, e a saída é abrir os Itens de início.
                estado = servico.status == .requiresApproval ? .precisaAprovar
                    : .indisponivel("O macOS não aceitou o ajudante (\(e.code)): \(e.localizedDescription)")
            }
        @unknown default:
            estado = .indisponivel("Situação do ajudante desconhecida.")
        }
    }

    /// Botão "Abrir Itens de início".
    func abrirItensDeInicio() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func conectarSePreciso() {
        guard conexao == nil else { return }
        let c = NSXPCConnection(machServiceName: Ventoinhas.servico, options: .privileged)
        c.setCodeSigningRequirement(Ventoinhas.requisitoAjudante)
        c.remoteObjectInterface = NSXPCInterface(with: ProtocoloVentoinhas.self)
        let caiu: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                self?.conexao = nil
                self?.versaoConferida = false
            }
        }
        c.invalidationHandler = caiu
        c.interruptionHandler = caiu
        c.resume()
        conexao = c
        conferirVersao()
    }

    private func proxy() -> ProtocoloVentoinhas? {
        conexao?.remoteObjectProxyWithErrorHandler { [weak self] e in
            let texto = e.localizedDescription
            Task { @MainActor in self?.erro = "Sem resposta do ajudante: \(texto)" }
        } as? ProtocoloVentoinhas
    }

    /// Depois de uma atualização do app, o ajudante antigo pode continuar rodando: encerra para o launchd abrir o novo.
    private func conferirVersao() {
        let minha = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        proxy()?.versao { [weak self] v in
            Task { @MainActor in
                guard let self else { return }
                if v != minha, !minha.isEmpty {
                    self.proxy()?.encerrar()
                    self.conexao?.invalidate()
                    self.conexao = nil
                } else {
                    self.versaoConferida = true
                }
            }
        }
    }

    private func mandar(_ rpm: [Double]) {
        guard let p = proxy() else { return }
        controlou = true
        p.definir(rpm: rpm.map { NSNumber(value: $0) }, validoPor: Self.validade) { [weak self] e in
            Task { @MainActor in self?.erro = e }
        }
    }

    private func mandarAutomatico() {
        guard servico.status == .enabled else { return }
        conectarSePreciso()
        proxy()?.automatico { [weak self] e in
            Task { @MainActor in self?.erro = e }
        }
    }
}
