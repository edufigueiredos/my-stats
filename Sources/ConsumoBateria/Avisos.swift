import Foundation
import UserNotifications

/// Sem delegate o sistema não mostra notificação com o app ativo (painel ou janela aberta).
final class ApresentadorAvisos: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

/// Avisos por notificação. Cada limite dispara uma vez por cruzamento e só rearma depois que a leitura
/// se afasta dele (histerese), para não repetir a cada leitura de 5 s.
@MainActor
final class Avisos {
    /// Quanto tempo o ritmo médio precisa ficar acima do limite antes de avisar.
    private static let persistenciaConsumo: TimeInterval = 2 * 60

    private var consumoDesde: Date?
    private var consumoAvisado = false
    private var bateriaAvisada = false
    private var carregouAvisado = false
    private var carregadorAvisado = false
    private var permissaoPedida = false
    private let apresentador = ApresentadorAvisos()

    /// Fora do .app (swift run, --foto) não há bundle id e o centro de notificações derruba o processo.
    private var disponivel: Bool { Bundle.main.bundleIdentifier != nil }

    init() {
        // O centro guarda o delegate de forma fraca; `apresentador` o mantém vivo. Registrado já na criação.
        if disponivel { UNUserNotificationCenter.current().delegate = apresentador }
    }

    // MARK: Permissão

    func pedirPermissaoSePreciso() {
        guard disponivel, !permissaoPedida else { return }
        permissaoPedida = true
        Task { @MainActor in
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    // MARK: Avaliação

    func avaliar(_ s: Situacao, ajustes: Ajustes) {
        let consumo = ajustes.avisoConsumoAcima, bateria = ajustes.avisoBateriaAbaixo
        let carregou = ajustes.avisoCarregouAte, fraco = ajustes.avisoCarregadorFraco
        guard disponivel else { return }
        if consumo.ligado || bateria.ligado || carregou.ligado || fraco.ligado { pedirPermissaoSePreciso() }

        let l = s.leitura
        let naBateria = s.estado == .descarregando || s.estado == .alto

        // Consumo alto: ritmo médio acima do limite por pelo menos 2 min seguidos.
        let ritmo = s.ritmoMedio ?? s.ritmoAgora
        if consumo.ligado, naBateria, ritmo < -consumo.limite {
            let desde = consumoDesde ?? l.data
            consumoDesde = desde
            if !consumoAvisado, l.data.timeIntervalSince(desde) >= Self.persistenciaConsumo {
                consumoAvisado = true
                enviar(id: "consumo", titulo: "Consumo alto",
                       corpo: "A bateria está gastando \(Formato.numero(-ritmo)) %/h, acima do seu limite de \(Int(consumo.limite)) %/h.")
            }
        } else {
            consumoDesde = nil
            if !consumo.ligado || !naBateria || ritmo > -consumo.limite * 0.8 { consumoAvisado = false }
        }

        // Bateria abaixo: só descarregando.
        if bateria.ligado, naBateria, Double(l.percentual) < bateria.limite {
            if !bateriaAvisada {
                bateriaAvisada = true
                enviar(id: "bateria", titulo: "Bateria baixa",
                       corpo: "Restam \(l.percentual)%. Ligue o carregador.")
            }
        } else if !bateria.ligado || l.naTomada || Double(l.percentual) >= bateria.limite + 5 {
            bateriaAvisada = false
        }

        // Carregou até: só carregando.
        if carregou.ligado, s.estado == .carregando, Double(l.percentual) >= carregou.limite {
            if !carregouAvisado {
                carregouAvisado = true
                enviar(id: "carregou", titulo: "Carga no limite",
                       corpo: "A bateria chegou a \(l.percentual)%. Já pode tirar da tomada.")
            }
        } else if !carregou.ligado || s.estado != .carregando || Double(l.percentual) < carregou.limite - 3 {
            carregouAvisado = false
        }

        // Carregador fraco: na tomada com potência menor que o limite.
        if fraco.ligado, l.naTomada, let w = s.detalhes.adaptadorW, w < fraco.limite {
            if !carregadorAvisado {
                carregadorAvisado = true
                enviar(id: "carregador", titulo: "Carregador fraco",
                       corpo: "O carregador entrega só \(Int(w)) W, abaixo de \(Int(fraco.limite)) W. A bateria pode não carregar.")
            }
        } else if !fraco.ligado || !l.naTomada || (s.detalhes.adaptadorW ?? .infinity) >= fraco.limite {
            carregadorAvisado = false
        }
    }

    // MARK: Envio

    private func enviar(id: String, titulo: String, corpo: String) {
        Task { @MainActor in
            let centro = UNUserNotificationCenter.current()
            let conteudo = UNMutableNotificationContent()
            conteudo.title = titulo
            conteudo.body = corpo
            conteudo.sound = .default
            let pedido = UNNotificationRequest(identifier: "consumo-bateria.\(id)", content: conteudo, trigger: nil)
            try? await centro.add(pedido)
        }
    }
}
