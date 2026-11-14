import AppKit
import Sparkle
import UserNotifications

/// Atualização automática pelas releases do GitHub, com o Sparkle (docs/atualizacao.md).
///
/// O Sparkle lê `SUFeedURL` (o appcast.xml da última release) uma vez por dia, confere a assinatura EdDSA do appcast e do DMG
/// e troca o app. O My Stats vive na barra de menus: uma janela do Sparkle aberta com o app em segundo plano ficaria escondida.
/// Por isso a busca agendada usa os "lembretes discretos": se há versão nova e o app não está em foco, sai uma notificação e o
/// menu do clique direito ganha "Atualizar para a versão X…"; a janela do Sparkle só abre nesse clique.
///
/// Build de desenvolvimento (`./build.sh`): o `SUFeedURL` sai do Info.plist do pacote, então a atualização fica desligada
/// e um app de teste nunca é trocado pelo publicado. Para testar com um appcast local: `MYSTATS_APPCAST=<url>` no ambiente.
@MainActor
final class Atualizador: NSObject {
    /// Versão nova encontrada pela busca agendada e ainda não vista.
    private(set) var pendente: String?
    let ligado: Bool

    private var controlador: SPUStandardUpdaterController?
    private let feedDeTeste = ProcessInfo.processInfo.environment["MYSTATS_APPCAST"]

    override init() {
        ligado = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil || feedDeTeste != nil
        super.init()
        guard ligado else { return }
        controlador = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        UNUserNotificationCenter.current().delegate = self
    }

    var versaoAtual: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }

    var podeBuscar: Bool { controlador?.updater.canCheckForUpdates ?? false }

    /// Abre a janela do Sparkle: busca agora, ou mostra a versão que já está esperando.
    func buscarAgora() {
        guard let c = controlador else { return }
        NSApp.activate(ignoringOtherApps: true)
        c.checkForUpdates(nil)
    }

    private func avisar(_ versao: String) {
        Task { @MainActor in
            let conteudo = UNMutableNotificationContent()
            conteudo.title = "My Stats \(versao) disponível"
            conteudo.body = "Clique para ver o que mudou e instalar."
            let pedido = UNNotificationRequest(identifier: "my-stats.atualizacao", content: conteudo, trigger: nil)
            try? await UNUserNotificationCenter.current().add(pedido)
        }
    }
}

extension Atualizador: SPUUpdaterDelegate {
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        MainActor.assumeIsolated { feedDeTeste }   // nil = SUFeedURL do Info.plist
    }
}

extension Atualizador: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        let versao = update.displayVersionString
        MainActor.assumeIsolated {
            guard !handleShowingUpdate else { return }
            if pendente != versao { avisar(versao) }
            pendente = versao
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { pendente = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { pendente = nil }
    }
}

extension Atualizador: UNUserNotificationCenterDelegate {
    /// Clique na notificação de versão nova: abre a janela do Sparkle. As outras notificações seguem como antes.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.notification.request.identifier == "my-stats.atualizacao" else { return }
        await MainActor.run { buscarAgora() }
    }

    /// Com um delegado, o macOS só mostra a notificação com o app em foco se pedirmos; mantém o comportamento de antes.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
