import AppKit
import Darwin
import Foundation
import IOKit

/// "Quem mais usa" por app: CPU, memória, disco (proc_pid_rusage) e GPU (IORegistry).
/// Agrupa por app como ConsumoApps.swift. Processos de root ou de outro usuário falham sem erro
/// (por isso kernel_task pode não aparecer). Só deve ser chamado com o painel aberto.
@MainActor
final class LeitorProcessos {
    private struct Amostra {
        var cpuNs: Double
        var lido: UInt64
        var gravado: UInt64
    }

    private var anterior: [Int32: Amostra] = [:]
    private var horario: Date?
    private var anteriorGPU: [Int32: Double] = [:]
    private var horarioGPU: Date?
    private var timebase = mach_timebase_info_data_t()
    private var paiCache: [Int32: Int32?] = [:]

    init() {
        mach_timebase_info(&timebase)
        if timebase.denom == 0 { timebase = mach_timebase_info_data_t(numer: 1, denom: 1) }
    }

    func medir(cpu: Bool, memoria: Bool, disco: Bool) -> ProcessosModulos {
        guard cpu || memoria || disco else { return ProcessosModulos() }
        let agora = Date()
        var atuais: [Int32: Amostra] = [:]
        var pegadas: [Int32: UInt64] = [:]
        for pid in listarPids() {
            var uso = rusage_info_v6()
            let ok = withUnsafeMutablePointer(to: &uso) { ptr in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
            }
            guard ok == 0 else { continue }
            // No Apple Silicon os tempos vêm em unidades de mach_absolute_time: converte para ns.
            let ns = Double(uso.ri_user_time &+ uso.ri_system_time) * Double(timebase.numer) / Double(timebase.denom)
            atuais[pid] = Amostra(cpuNs: ns, lido: uso.ri_diskio_bytesread, gravado: uso.ri_diskio_byteswritten)
            pegadas[pid] = uso.ri_phys_footprint
        }
        let antes = anterior
        let dt = horario.map { agora.timeIntervalSince($0) } ?? 0
        anterior = atuais
        horario = agora

        paiCache.removeAll(keepingCapacity: true)
        let donos = mapaDeApps()
        var grupos: [Int32: (id: String, nome: String)] = [:]
        for pid in atuais.keys { grupos[pid] = grupo(de: pid, donos: donos) }

        var r = ProcessosModulos()
        if memoria {
            var porGrupo: [String: (String, Double, Double)] = [:]
            for (pid, b) in pegadas {
                guard let g = grupos[pid] else { continue }
                porGrupo[g.id, default: (g.nome, 0, 0)].1 += Double(b)
            }
            r.memoria = topo(porGrupo)
        }
        // A primeira medição não tem diferença: CPU e disco ficam vazios.
        if dt > 0.2, !antes.isEmpty {
            var cpuG: [String: (String, Double, Double)] = [:]
            var discoG: [String: (String, Double, Double)] = [:]
            for (pid, a) in atuais {
                guard let ant = antes[pid], let g = grupos[pid] else { continue }
                if cpu, a.cpuNs >= ant.cpuNs {
                    cpuG[g.id, default: (g.nome, 0, 0)].1 += (a.cpuNs - ant.cpuNs) / (dt * 1e9) * 100
                }
                if disco {
                    let l = a.lido >= ant.lido ? Double(a.lido - ant.lido) / dt : 0
                    let e = a.gravado >= ant.gravado ? Double(a.gravado - ant.gravado) / dt : 0
                    discoG[g.id, default: (g.nome, 0, 0)].1 += l
                    discoG[g.id]!.2 += e
                }
            }
            if cpu { r.cpu = topo(cpuG) }
            if disco { r.disco = topo(discoG, somaDupla: true) }
        }
        return r
    }

    /// Uso de GPU por processo: filhos AGXDeviceUserClient do IOAccelerator, com "AppUsage".
    /// nil se a estrutura não existir (a seção some). A primeira chamada devolve lista vazia.
    func medirGPU() -> [ProcessoUso]? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }

        var acumulado: [Int32: (nome: String, ns: Double)] = [:]
        var viuClientes = false
        while case let acel = IOIteratorNext(iter), acel != 0 {
            defer { IOObjectRelease(acel) }
            var filhos: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(acel, kIOServicePlane, &filhos) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(filhos) }
            while case let f = IOIteratorNext(filhos), f != 0 {
                defer { IOObjectRelease(f) }
                guard let criador = IORegistryEntryCreateCFProperty(f, "IOUserClientCreator" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
                      let uso = IORegistryEntryCreateCFProperty(f, "AppUsage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [[String: Any]]
                else { continue }
                viuClientes = true
                // Formato: "pid 123, Nome".
                let partes = criador.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard let primeiro = partes.first, primeiro.hasPrefix("pid "),
                      let pid = Int32(primeiro.dropFirst(4)) else { continue }
                let total = uso.reduce(0.0) { $0 + (($1["accumulatedGPUTime"] as? NSNumber)?.doubleValue ?? 0) }
                let nome = partes.count > 1 ? partes[1] : "pid \(pid)"
                acumulado[pid, default: (nome, 0)].ns += total
            }
        }
        guard viuClientes else { return nil }

        let agora = Date()
        let antes = anteriorGPU
        let dt = horarioGPU.map { agora.timeIntervalSince($0) } ?? 0
        anteriorGPU = acumulado.mapValues { $0.ns }
        horarioGPU = agora
        guard dt > 0.2, !antes.isEmpty else { return [] }

        let donos = mapaDeApps()
        paiCache.removeAll(keepingCapacity: true)
        var porGrupo: [String: (String, Double, Double)] = [:]
        for (pid, a) in acumulado {
            guard let ant = antes[pid], a.ns >= ant else { continue }
            let pct = (a.ns - ant) / (dt * 1e9) * 100
            let g = donos[pid].map { ($0.id, $0.nome) } ?? grupo(de: pid, donos: donos)
            porGrupo[g.0, default: (g.1, 0, 0)].1 += pct
        }
        return topo(porGrupo.mapValues { ($0.0, min($0.1, 100), 0) })
    }

    // MARK: - Ordenação

    /// Ordena por valor, corta em 5 e calcula a fração em relação ao maior. Ignora zeros.
    private func topo(_ g: [String: (String, Double, Double)], somaDupla: Bool = false) -> [ProcessoUso] {
        let itens = g.filter { somaDupla ? ($0.value.1 + $0.value.2) > 0 : $0.value.1 > 0 }
            .sorted { somaDupla ? ($0.value.1 + $0.value.2) > ($1.value.1 + $1.value.2) : $0.value.1 > $1.value.1 }
            .prefix(5)
        let maior = itens.map { somaDupla ? $0.value.1 + $0.value.2 : $0.value.1 }.max() ?? 0
        guard maior > 0 else { return [] }
        return itens.map { id, v in
            let base = somaDupla ? v.1 + v.2 : v.1
            return ProcessoUso(id: id, nome: v.0, valor: v.1, valor2: somaDupla ? v.2 : nil, fracao: base / maior)
        }
    }

    // MARK: - Processos e agrupamento

    private func listarPids() -> [Int32] {
        let bytes = proc_listallpids(nil, 0)
        guard bytes > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(bytes) / MemoryLayout<Int32>.size + 64)
        let escrito = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard escrito > 0 else { return [] }
        let n = min(Int(escrito) / MemoryLayout<Int32>.size, pids.count)
        return pids.prefix(n).filter { $0 > 0 }
    }

    private func mapaDeApps() -> [Int32: (id: String, nome: String)] {
        var mapa: [Int32: (id: String, nome: String)] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited || app.bundleIdentifier != nil {
            guard let nome = app.localizedName else { continue }
            mapa[app.processIdentifier] = (app.bundleIdentifier ?? nome, nome)
        }
        return mapa
    }

    private func pai(de pid: Int32) -> Int32? {
        if let c = paiCache[pid] { return c }
        var info = proc_bsdinfo()
        let tam = Int32(MemoryLayout<proc_bsdinfo>.size)
        var resultado: Int32? = nil
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, tam) == tam {
            let ppid = Int32(bitPattern: info.pbi_ppid)
            resultado = ppid > 1 ? ppid : nil
        }
        paiCache[pid] = .some(resultado)
        return resultado
    }

    private func nomeProcesso(_ pid: Int32) -> String {
        var buf = [CChar](repeating: 0, count: 256)
        let n = proc_name(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(decoding: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self) : "pid \(pid)"
    }

    /// Sobe pelos pais até um app em execução; sem app, usa o nome do próprio processo.
    private func grupo(de pid: Int32, donos: [Int32: (id: String, nome: String)]) -> (id: String, nome: String) {
        var atual = pid
        for _ in 0..<12 {
            if let d = donos[atual] { return d }
            guard let p = pai(de: atual) else { break }
            atual = p
        }
        let nome = nomeProcesso(pid)
        return ("proc:" + nome, nome)
    }
}
