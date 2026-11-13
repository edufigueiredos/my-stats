import AppKit
import Darwin
import Foundation

/// Estima o gasto de cada app repartindo os watts do sistema pela energia que cada processo usou
/// entre duas medições (proc_pid_rusage, sem privilégio de administrador).
///
/// É uma ESTIMATIVA, não uma medida. Fica de fora: processos de root e de outros usuários (o macOS nega
/// a leitura sem privilégio), e a tela, a GPU e o rádio, que não são atribuídos por processo; o que
/// sobra desses vai diluído na fração de cada grupo ou em "Sistema e outros".
@MainActor
final class MedidorApps {
    private struct Ultimo {
        var energia: UInt64
        var cpu: UInt64
    }

    private var anterior: [Int32: Ultimo] = [:]
    private static let idSistema = "sistema"
    private static let nomeSistema = "Sistema e outros"

    func medir(wattsSistema: Double) -> [ConsumoApp] {
        let atuais = lerProcessos()
        let primeira = anterior.isEmpty
        let antes = anterior
        anterior = atuais
        guard !primeira, wattsSistema > 0 else { return [] }

        // Diferenças por pid (só quem já existia na medição anterior).
        var difs: [Int32: (energia: Double, cpu: Double)] = [:]
        for (pid, agora) in atuais {
            guard let ant = antes[pid] else { continue }
            let de = agora.energia >= ant.energia ? Double(agora.energia - ant.energia) : 0
            let dc = agora.cpu >= ant.cpu ? Double(agora.cpu - ant.cpu) : 0
            difs[pid] = (de, dc)
        }
        // Peso: energia; se vier zerada em tudo, tempo de CPU.
        let totalEnergia = difs.values.reduce(0) { $0 + $1.energia }
        let usarEnergia = totalEnergia > 0
        let totalPeso = usarEnergia ? totalEnergia : difs.values.reduce(0) { $0 + $1.cpu }
        guard totalPeso > 0 else { return [] }

        let donos = mapaDeApps()
        var grupos: [String: (nome: String, peso: Double)] = [:]
        for (pid, d) in difs {
            let peso = usarEnergia ? d.energia : d.cpu
            guard peso > 0 else { continue }
            let (id, nome) = grupo(de: pid, donos: donos)
            grupos[id, default: (nome, 0)].peso += peso
        }

        var itens = grupos.map { id, g in
            ConsumoApp(id: id, nome: g.nome, watts: wattsSistema * g.peso / totalPeso, fracao: 0)
        }
        // Menos de 1% do total fica de fora.
        itens = itens.filter { $0.watts >= wattsSistema * 0.01 }
        let sistema = itens.first { $0.id == Self.idSistema }
        var apps = itens.filter { $0.id != Self.idSistema }.sorted { $0.watts > $1.watts }
        apps = Array(apps.prefix(sistema == nil ? 6 : 5))
        if let sistema { apps.append(sistema) }
        let maior = apps.map(\.watts).max() ?? 0
        guard maior > 0 else { return [] }
        return apps.map { var a = $0; a.fracao = a.watts / maior; return a }
    }

    // MARK: - Leitura dos processos

    private func lerProcessos() -> [Int32: Ultimo] {
        let bytes = proc_listallpids(nil, 0)
        guard bytes > 0 else { return [:] }
        var pids = [Int32](repeating: 0, count: Int(bytes) / MemoryLayout<Int32>.size + 64)
        let escrito = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard escrito > 0 else { return [:] }
        let n = min(Int(escrito) / MemoryLayout<Int32>.size, pids.count)

        var resultado: [Int32: Ultimo] = [:]
        for pid in pids.prefix(n) where pid > 0 {
            var uso = rusage_info_v6()
            // Falha (outro usuário, root, processo que acabou) é ignorada sem erro.
            let ok = withUnsafeMutablePointer(to: &uso) { ptr in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
            }
            guard ok == 0 else { continue }
            let energia = uso.ri_energy_nj != 0 ? uso.ri_energy_nj : uso.ri_billed_energy
            resultado[pid] = Ultimo(energia: energia, cpu: uso.ri_user_time &+ uso.ri_system_time)
        }
        return resultado
    }

    // MARK: - Agrupamento por app

    private func mapaDeApps() -> [Int32: (id: String, nome: String)] {
        var mapa: [Int32: (id: String, nome: String)] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited || app.bundleIdentifier != nil {
            guard let nome = app.localizedName else { continue }
            mapa[app.processIdentifier] = (app.bundleIdentifier ?? nome, nome)
        }
        return mapa
    }

    private func pai(de pid: Int32) -> Int32? {
        var info = proc_bsdinfo()
        let tam = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, tam) == tam else { return nil }
        let ppid = Int32(bitPattern: info.pbi_ppid)
        return ppid > 1 ? ppid : nil
    }

    /// Sobe pela árvore de pais até achar um app em execução; sem dono, vai para "Sistema e outros".
    private func grupo(de pid: Int32, donos: [Int32: (id: String, nome: String)]) -> (String, String) {
        var atual = pid
        for _ in 0..<12 {
            if let dono = donos[atual] {
                return (dono.id, dono.nome)
            }
            guard let p = pai(de: atual) else { break }
            atual = p
        }
        return (Self.idSistema, Self.nomeSistema)
    }
}
