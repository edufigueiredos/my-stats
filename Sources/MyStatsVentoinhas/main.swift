import Foundation
import VentoinhasXPC

// Ajudante das ventoinhas do My Stats. Roda como root pelo launchd (registrado pelo app com SMAppService) e só
// atende o My Stats assinado pelo Developer ID do Eduardo. Ele não decide nada: aplica os alvos que o app manda
// e devolve as ventoinhas ao macOS quando o prazo vence, quando o app desconecta, ao iniciar e ao encerrar.

/// Estado único, sempre mexido na fila `fila`.
final class Central: @unchecked Sendable {
    let fila = DispatchQueue(label: "ventoinhas")
    private let controle = ControleSMC()
    private var prazo: DispatchSourceTimer?
    /// Conexão que mandou o último alvo; se ela cair, as ventoinhas voltam ao macOS.
    private var dono: ObjectIdentifier?

    init() {
        // Ao iniciar, ninguém controla nada: tudo com o macOS (vale também depois de uma queda do ajudante).
        controle?.soltarTodas()
    }

    func definir(_ rpm: [Double], validoPor: Double, de conexao: ObjectIdentifier) -> String? {
        guard let controle else { return "sem acesso ao SMC" }
        guard controle.quantidade > 0 else { return "este Mac não tem ventoinha" }
        var erros: [String] = []
        for i in 0..<controle.quantidade {
            let alvo = i < rpm.count ? rpm[i] : Ventoinhas.automatico
            if alvo < 0 {
                controle.soltar(i)
            } else if let e = controle.definir(i, rpm: alvo) {
                erros.append(e)
            }
        }
        dono = conexao
        armarPrazo(min(max(validoPor, 2), 30))
        if !erros.isEmpty { controle.soltarTodas() }
        return erros.first
    }

    func soltar() {
        prazo?.cancel()
        prazo = nil
        dono = nil
        controle?.soltarTodas()
    }

    func caiu(_ conexao: ObjectIdentifier) {
        if dono == nil || dono == conexao { soltar() }
    }

    private func armarPrazo(_ segundos: Double) {
        prazo?.cancel()
        let t = DispatchSource.makeTimerSource(queue: fila)
        t.schedule(deadline: .now() + segundos)
        t.setEventHandler { [weak self] in self?.soltar() }
        t.resume()
        prazo = t
    }
}

/// Um objeto por conexão, para saber quem é o dono do controle.
final class Sessao: NSObject, ProtocoloVentoinhas, @unchecked Sendable {
    private let central: Central
    private let conexao: ObjectIdentifier

    init(central: Central, conexao: NSXPCConnection) {
        self.central = central
        self.conexao = ObjectIdentifier(conexao)
    }

    func versao(resposta: @escaping (String) -> Void) {
        resposta(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")
    }

    func definir(rpm: [NSNumber], validoPor: Double, resposta: @escaping (String?) -> Void) {
        let valores = rpm.map(\.doubleValue)
        let c = conexao
        central.fila.async { resposta(self.central.definir(valores, validoPor: validoPor, de: c)) }
    }

    func automatico(resposta: @escaping (String?) -> Void) {
        central.fila.async {
            self.central.soltar()
            resposta(nil)
        }
    }

    func encerrar() {
        central.fila.async {
            self.central.soltar()
            exit(0)
        }
    }
}

final class Porteiro: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    let central: Central
    init(central: Central) { self.central = central }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection conexao: NSXPCConnection) -> Bool {
        // O XPC confere a assinatura de quem chama antes de entregar qualquer mensagem.
        conexao.setCodeSigningRequirement(Ventoinhas.requisitoApp)
        conexao.exportedInterface = NSXPCInterface(with: ProtocoloVentoinhas.self)
        conexao.exportedObject = Sessao(central: central, conexao: conexao)
        let central = self.central
        let id = ObjectIdentifier(conexao)
        let fim: @Sendable () -> Void = { central.fila.async { central.caiu(id) } }
        conexao.invalidationHandler = fim
        conexao.interruptionHandler = fim
        conexao.resume()
        return true
    }
}

let central = Central()
let porteiro = Porteiro(central: central)

// Encerrado pelo launchd (desinstalar, desligar): devolve as ventoinhas antes de sair.
var fontesDeSinal: [DispatchSourceSignal] = []
for sinal in [SIGTERM, SIGINT, SIGHUP] {
    signal(sinal, SIG_IGN)
    let fonte = DispatchSource.makeSignalSource(signal: sinal, queue: central.fila)
    fonte.setEventHandler {
        central.soltar()
        exit(0)
    }
    fonte.resume()
    fontesDeSinal.append(fonte)
}

let ouvinte = NSXPCListener(machServiceName: Ventoinhas.servico)
ouvinte.delegate = porteiro
ouvinte.resume()
RunLoop.main.run()
