import AppKit
import CoreGraphics
import Foundation
import IOKit

/// Lê o uso da GPU no IORegistry (IOAccelerator / PerformanceStatistics) e as telas. Sem root.
/// codificarVideo e decodificarVideo ficam sempre nil: não há API pública sem root para o uso dos motores de vídeo.
@MainActor
final class LeitorGPU {
    init() {}

    func ler() -> LeituraGPU? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }

        var l = LeituraGPU()
        var achou = false
        while case let servico = IOIteratorNext(iter), servico != 0 {
            defer { IOObjectRelease(servico) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(servico, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any] else { continue }
            let stats = dict["PerformanceStatistics"] as? [String: Any] ?? [:]
            let uso = Self.numero(stats["Device Utilization %"]) ?? Self.numero(stats["GPU Activity(%)"])
            let mem = Self.numero(stats["In use system memory"]) ?? Self.numero(stats["inUseSystemMemory"])
            // Mais de uma GPU: fica a de maior uso.
            if achou, (uso ?? 0) <= (l.uso ?? 0) { continue }
            achou = true
            l.uso = uso.map { min(max($0, 0), 100) }
            l.memoriaEmUsoBytes = mem.map { UInt64(max($0, 0)) }
            l.nucleos = Self.numero(dict["gpu-core-count"]).map { Int($0) }
            l.nome = (dict["model"] as? String) ?? (dict["IOClass"] as? String)
        }
        guard achou else { return nil }
        l.telas = lerTelas()
        return l
    }

    private func lerTelas() -> [TelaGPU] {
        NSScreen.screens.map { tela in
            let id = (tela.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            let integrada = id.map { CGDisplayIsBuiltin($0) != 0 } ?? false
            let hz = tela.maximumFramesPerSecond
            return TelaGPU(nome: integrada ? "Integrada" : (tela.localizedName.isEmpty ? "Externa" : tela.localizedName),
                           integrada: integrada, hz: hz > 0 ? hz : nil)
        }
    }

    private static func numero(_ v: Any?) -> Double? {
        (v as? NSNumber)?.doubleValue
    }
}
