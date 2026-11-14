import Darwin
import Foundation

/// Lê a memória (host_statistics64), a pressão e o swap. Sem root.
@MainActor
final class LeitorMemoria {
    init() {}

    func ler() -> LeituraMemoria? {
        var stats = vm_statistics64_data_t()
        var qtd = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(qtd)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &qtd)
            }
        }
        guard r == KERN_SUCCESS else { return nil }

        var total: UInt64 = 0
        var tamTotal = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &total, &tamTotal, nil, 0) == 0, total > 0 else { return nil }
        var tamPagina: Int32 = 0
        var tamP = MemoryLayout<Int32>.size
        let pagina: UInt64 = sysctlbyname("hw.pagesize", &tamPagina, &tamP, nil, 0) == 0 && tamPagina > 0 ? UInt64(tamPagina) : 16384
        func bytes(_ paginas: UInt64) -> UInt64 { paginas * pagina }

        let interna = UInt64(stats.internal_page_count)
        let purgavel = UInt64(stats.purgeable_count)
        let apps = interna > purgavel ? interna - purgavel : 0

        var l = LeituraMemoria()
        l.totalBytes = total
        l.appsBytes = bytes(apps)
        l.fixaBytes = bytes(UInt64(stats.wire_count))
        l.comprimidaBytes = bytes(UInt64(stats.compressor_page_count))
        l.cacheBytes = bytes(UInt64(stats.external_page_count) + purgavel)
        l.livreBytes = bytes(UInt64(stats.free_count) + UInt64(stats.speculative_count))

        // Pressão: 1 normal, 2 aviso, 4 crítica.
        var nivel: Int32 = 1
        var tam = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &nivel, &tam, nil, 0) == 0 {
            l.pressao = nivel >= 4 ? .critica : (nivel >= 2 ? .aviso : .normal)
        }
        // Percentual de pressão = 100 − porcentagem de memória livre do kernel.
        var livre: Int32 = 0
        tam = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_level", &livre, &tam, nil, 0) == 0 {
            l.pressaoPercentual = min(max(100 - Double(livre), 0), 100)
        }

        var swap = xsw_usage()
        var tamSwap = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &tamSwap, nil, 0) == 0 {
            l.swapUsadoBytes = swap.xsu_used
        }
        return l
    }
}
