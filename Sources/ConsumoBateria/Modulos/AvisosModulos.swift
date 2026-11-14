import Foundation
import UserNotifications

/// Avisos por notificação dos módulos. Cada aviso ligado, de módulo ligado, dispara uma vez quando a condição dura
/// `minutos` seguidos e só rearma depois que o valor sai dela com folga de 5% do limite.
@MainActor
final class AvisosModulos {
    private struct Estado {
        var desde: Date?
        var avisado = false
    }

    private var estados: [String: Estado] = [:]
    private var permissaoPedida = false

    /// Fora do .app (swift run, --foto) não há bundle id e o centro de notificações derruba o processo.
    private var disponivel: Bool { Bundle.main.bundleIdentifier != nil }

    private static let gib = 1024.0 * 1024 * 1024

    func avaliar(_ l: LeiturasModulos, ajustes: AjustesModulos) {
        var vivos = Set<String>()
        for a in ajustes.modulos where a.ligado {
            for aviso in a.avisos where aviso.ligado {
                let chave = "\(a.modulo.rawValue).\(aviso.tipo.rawValue)"
                vivos.insert(chave)
                pedirPermissaoSePreciso()
                avaliar(aviso, modulo: a.modulo, leituras: l, chave: chave)
            }
        }
        // Aviso desligado ou módulo desligado: esquece o estado, para começar do zero quando voltar.
        for chave in estados.keys where !vivos.contains(chave) { estados[chave] = nil }
    }

    /// Resultado de olhar a condição: `nil` = sem leitura.
    private struct Olhada {
        var cumpre: Bool
        var livre: Bool       // saiu da condição com histerese
        var titulo: String
        var corpo: String
    }

    private func avaliar(_ aviso: AvisoModulo, modulo m: Modulo, leituras l: LeiturasModulos, chave: String) {
        guard let o = olhar(aviso, modulo: m, leituras: l) else {
            // Sem leitura: zera só o "desde"; `avisado` fica, para perdas intermitentes não renotificarem.
            var e = estados[chave] ?? Estado()
            e.desde = nil
            estados[chave] = e
            return
        }
        var e = estados[chave] ?? Estado()
        if o.cumpre {
            let desde = e.desde ?? l.data
            e.desde = desde
            if !e.avisado, l.data.timeIntervalSince(desde) >= aviso.minutos * 60 {
                e.avisado = true
                enviar(id: chave, titulo: o.titulo, corpo: o.corpo)
            }
        } else {
            e.desde = nil
            if e.avisado, o.livre { e.avisado = false }
        }
        estados[chave] = e
    }

    private func n(_ v: Double) -> String { Formato.numero(v, casas: v.rounded() == v ? 0 : 1) }

    private func ha(_ aviso: AvisoModulo) -> String { aviso.minutos > 0 ? " há \(n(aviso.minutos)) min" : "" }

    private func olhar(_ aviso: AvisoModulo, modulo m: Modulo, leituras l: LeiturasModulos) -> Olhada? {
        let lim = aviso.limite
        switch aviso.tipo {
        case .usoAcima:
            guard let v = (m == .gpu ? l.gpu?.uso : l.cpu?.uso) else { return nil }
            return Olhada(cumpre: v > lim, livre: v < lim * 0.95,
                          titulo: "\(m.titulo) acima de \(n(lim))%\(ha(aviso))",
                          corpo: "Uso agora: \(n(v))%.")
        case .temperaturaAcima:
            guard let s = l.sensores else { return nil }
            guard let v = (m == .gpu ? s.gpuC : s.cpuC) else { return nil }
            return Olhada(cumpre: v > lim, livre: v < lim * 0.95,
                          titulo: "\(m.titulo) acima de \(n(lim)) °C\(ha(aviso))",
                          corpo: "Temperatura agora: \(n(v)) °C.")
        case .pressaoAlta:
            guard let mem = l.memoria else { return nil }
            let alta = mem.pressao != .normal
            return Olhada(cumpre: alta, livre: !alta,
                          titulo: "Pressão de memória alta\(ha(aviso))",
                          corpo: "Feche apps pesados para liberar memória. Pressão: \(mem.pressao.titulo.lowercased()).")
        case .swapAcima:
            guard let mem = l.memoria else { return nil }
            let v = Double(mem.swapUsadoBytes) / Self.gib
            return Olhada(cumpre: v > lim, livre: v < lim * 0.95,
                          titulo: "Swap acima de \(n(lim)) GB",
                          corpo: "O Mac está usando \(Formato.bytesMemoria(mem.swapUsadoBytes)) de swap.")
        case .espacoAbaixo:
            guard let d = l.disco else { return nil }
            let internos = d.volumes.filter { $0.interno && $0.totalBytes > 0 }
            let candidatos = internos.isEmpty ? d.volumes.filter { $0.totalBytes > 0 } : internos
            guard let pior = candidatos.min(by: { livrePct($0) < livrePct($1) }) else { return nil }
            let v = livrePct(pior)
            return Olhada(cumpre: v < lim, livre: v > lim * 1.05,
                          titulo: "Pouco espaço em \(pior.nome)",
                          corpo: "Restam \(Formato.bytesDisco(pior.livreBytes)) livres (\(n(v))%).")
        case .latenciaAcima:
            guard let r = l.rede, r.conectado, let v = r.latenciaMs else { return nil }
            return Olhada(cumpre: v > lim, livre: v < lim * 0.95,
                          titulo: "Latência acima de \(n(lim)) ms\(ha(aviso))",
                          corpo: "Latência agora: \(n(v)) ms para \(r.alvoLatencia).")
        case .semRede:
            guard let r = l.rede else { return nil }
            return Olhada(cumpre: !r.conectado, livre: r.conectado,
                          titulo: "Sem rede\(ha(aviso))",
                          corpo: "O Mac está sem conexão com a internet.")
        }
    }

    private func livrePct(_ v: VolumeDisco) -> Double {
        Double(min(v.livreBytes, v.totalBytes)) / Double(v.totalBytes) * 100
    }

    // MARK: Envio

    private func pedirPermissaoSePreciso() {
        guard disponivel, !permissaoPedida else { return }
        permissaoPedida = true
        Task { @MainActor in
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    private func enviar(id: String, titulo: String, corpo: String) {
        guard disponivel else { return }
        Task { @MainActor in
            let conteudo = UNMutableNotificationContent()
            conteudo.title = titulo
            conteudo.body = corpo
            conteudo.sound = .default
            let pedido = UNNotificationRequest(identifier: "consumo-bateria.modulo.\(id)", content: conteudo, trigger: nil)
            try? await UNUserNotificationCenter.current().add(pedido)
        }
    }
}
