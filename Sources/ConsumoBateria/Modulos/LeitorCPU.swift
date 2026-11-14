@preconcurrency import Darwin
import Foundation
import IOKit

/// Lê o uso de CPU por núcleo (host_processor_info), carga média, processos e threads. Sem root.
@MainActor
final class LeitorCPU {
    private struct Ticks { var usuario: UInt64; var sistema: UInt64; var ocioso: UInt64 }
    private var anterior: [Ticks] = []

    init() {}

    func ler() -> LeituraCPU? {
        guard let atuais = lerTicks(), !atuais.isEmpty else { return nil }
        // Na primeira chamada não há ticks anteriores: vale a média desde o boot.
        let base = anterior.count == atuais.count ? anterior : [Ticks](repeating: Ticks(usuario: 0, sistema: 0, ocioso: 0), count: atuais.count)
        anterior = atuais

        var porNucleo: [Double] = []
        var somaU = 0.0, somaS = 0.0, somaTotal = 0.0
        for (agora, antes) in zip(atuais, base) {
            let u = Double(agora.usuario &- antes.usuario)
            let s = Double(agora.sistema &- antes.sistema)
            let o = Double(agora.ocioso &- antes.ocioso)
            let total = u + s + o
            porNucleo.append(total > 0 ? (u + s) / total * 100 : 0)
            somaU += u; somaS += s; somaTotal += total
        }
        guard somaTotal > 0 else { return nil }

        // Ordem real dos núcleos: o IORegistry diz o cluster (E, M, P) de cada logical-cpu-id.
        // host_processor_info lista por logical-cpu-id; devolvemos o nível mais alto primeiro.
        let n = porNucleo.count
        var desempenho = Self.sysctlInt("hw.perflevel0.logicalcpu") ?? n
        var eficiencia = Self.sysctlInt("hw.perflevel1.logicalcpu") ?? 0
        if desempenho + eficiencia != n || desempenho <= 0 { desempenho = n; eficiencia = 0 }
        if eficiencia > 0 {
            if let clusters = Self.clustersPorNucleo(), clusters.count == n {
                let peso: [Character: Int] = ["P": 2, "M": 1, "E": 0]
                let ordem = (0..<n).sorted {
                    let a = peso[clusters[$0]] ?? 0, b = peso[clusters[$1]] ?? 0
                    return a != b ? a > b : $0 < $1
                }
                porNucleo = ordem.map { porNucleo[$0] }
            } else {
                // Sem o IORegistry, assume que o nível 1 vem primeiro (verificado em M5 Max).
                let efi = Array(porNucleo.prefix(eficiencia))
                porNucleo = Array(porNucleo.dropFirst(eficiencia)) + efi
            }
        }

        var carga = [Double](repeating: 0, count: 3)
        let cargaOk = getloadavg(&carga, 3) == 3

        let (processos, threads) = contarProcessos()

        return LeituraCPU(
            uso: (somaU + somaS) / somaTotal * 100,
            usuario: somaU / somaTotal * 100,
            sistema: somaS / somaTotal * 100,
            nucleos: porNucleo,
            nucleosDesempenho: desempenho,
            nucleosEficiencia: eficiencia,
            nomeNivel0: Self.sysctlTexto("hw.perflevel0.name"),
            nomeNivel1: Self.sysctlTexto("hw.perflevel1.name"),
            cargaMedia: cargaOk ? carga : [],
            processos: processos,
            threads: threads)
    }

    /// Cluster ("E", "M" ou "P") de cada núcleo, na ordem do logical-cpu-id.
    private static func clustersPorNucleo() -> [Character]? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPlatformDevice"), &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        var achados: [Int: Character] = [:]
        while case let e = IOIteratorNext(iter), e != 0 {
            defer { IOObjectRelease(e) }
            guard let id = IORegistryEntryCreateCFProperty(e, "logical-cpu-id" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int,
                  let d = IORegistryEntryCreateCFProperty(e, "cluster-type" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
                  let c = d.first.flatMap({ Character(UnicodeScalar($0)) }) else { continue }
            achados[id] = c
        }
        guard !achados.isEmpty, achados.keys.sorted() == Array(0..<achados.count) else { return nil }
        return (0..<achados.count).map { achados[$0]! }
    }

    private static func sysctlTexto(_ nome: String) -> String? {
        var tam = 0
        guard sysctlbyname(nome, nil, &tam, nil, 0) == 0, tam > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: tam)
        guard sysctlbyname(nome, &buf, &tam, nil, 0) == 0 else { return nil }
        return String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    // MARK: - Leitura

    private func lerTicks() -> [Ticks]? {
        var nucleos: natural_t = 0
        var info: processor_info_array_t? = nil
        var qtd: mach_msg_type_number_t = 0
        let r = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &nucleos, &info, &qtd)
        guard r == KERN_SUCCESS, let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(qtd) * vm_size_t(MemoryLayout<integer_t>.size)) }
        let passo = Int(CPU_STATE_MAX)
        var lista: [Ticks] = []
        for i in 0..<Int(nucleos) {
            let b = i * passo
            lista.append(Ticks(
                usuario: UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_USER)])) + UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_NICE)])),
                sistema: UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_SYSTEM)])),
                ocioso: UInt64(UInt32(bitPattern: info[b + Int(CPU_STATE_IDLE)]))))
        }
        return lista
    }

    /// Processos = proc_listallpids. Threads = soma de pti_threadnum; se mais de 10% falharem, nil.
    private func contarProcessos() -> (Int?, Int?) {
        let bytes = proc_listallpids(nil, 0)
        guard bytes > 0 else { return (nil, nil) }
        var pids = [Int32](repeating: 0, count: Int(bytes) / MemoryLayout<Int32>.size + 64)
        let escrito = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard escrito > 0 else { return (nil, nil) }
        let n = min(Int(escrito) / MemoryLayout<Int32>.size, pids.count)
        var threads = 0, falhas = 0, total = 0
        for pid in pids.prefix(n) where pid > 0 {
            total += 1
            var info = proc_taskinfo()
            let tam = Int32(MemoryLayout<proc_taskinfo>.size)
            if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, tam) == tam {
                threads += Int(info.pti_threadnum)
            } else {
                falhas += 1
            }
        }
        guard total > 0 else { return (nil, nil) }
        return (total, Double(falhas) / Double(total) > 0.10 ? nil : threads)
    }

    static func sysctlInt(_ nome: String) -> Int? {
        var v: Int32 = 0
        var tam = MemoryLayout<Int32>.size
        guard sysctlbyname(nome, &v, &tam, nil, 0) == 0 else { return nil }
        return Int(v)
    }
}
