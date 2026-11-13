import Foundation
import IOKit
import IOKit.ps

/// Uma leitura do serviço AppleSmartBattery.
struct LeituraBateria: Sendable {
    var data: Date
    /// % mostrado pelo sistema (CurrentCapacity; no Apple Silicon já vem em %).
    var percentual: Int
    /// Carga atual real, em mAh (AppleRawCurrentCapacity).
    var cargaMah: Int
    /// Capacidade cheia real, em mAh (AppleRawMaxCapacity; nunca MaxCapacity, que vem em %).
    var capacidadeMah: Int
    /// Corrente instantânea em mA: negativa descarregando, positiva carregando.
    var correnteMa: Int
    /// Corrente média do próprio controlador (Amperage), em mA.
    var correnteMediaMa: Int
    var tensaoMv: Int
    var carregando: Bool
    var naTomada: Bool
    var cheia: Bool
    /// Minutos restantes segundo o sistema; nil enquanto ele calcula.
    var minutosSistema: Int?

    /// Ritmo instantâneo em % da capacidade cheia por hora.
    var ritmoInstantaneo: Double {
        guard capacidadeMah > 0 else { return 0 }
        return Double(correnteMa) / Double(capacidadeMah) * 100
    }

    var watts: Double { Double(tensaoMv) * Double(correnteMa) / 1_000_000 }
}

enum LeitorBateria {
    static func ler() -> LeituraBateria? {
        let servico = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard servico != 0 else { return nil }
        defer { IOObjectRelease(servico) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(servico, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
        // Em alguns Macs as chaves "Raw" só aparecem dentro de BatteryData.
        let dados = dict["BatteryData"] as? [String: Any] ?? [:]

        func inteiro(_ chave: String) -> Int? {
            // Os valores negativos vêm como UInt64; int64Value devolve o padrão de bits com sinal.
            if let n = dict[chave] as? NSNumber { return Int(n.int64Value) }
            if let n = dados[chave] as? NSNumber { return Int(n.int64Value) }
            return nil
        }
        func booleano(_ chave: String) -> Bool {
            (dict[chave] as? NSNumber)?.boolValue ?? (dict[chave] as? Bool) ?? false
        }

        let capacidade = inteiro("AppleRawMaxCapacity") ?? inteiro("FullChargeCapacity")
            ?? inteiro("NominalChargeCapacity") ?? 0
        let instantanea = inteiro("InstantAmperage") ?? inteiro("Amperage") ?? 0
        let tempo = inteiro("TimeRemaining") ?? inteiro("AvgTimeToEmpty")

        return LeituraBateria(
            data: Date(),
            percentual: inteiro("CurrentCapacity") ?? 0,
            cargaMah: inteiro("AppleRawCurrentCapacity") ?? inteiro("RemainingCapacity") ?? 0,
            capacidadeMah: capacidade,
            correnteMa: instantanea,
            correnteMediaMa: inteiro("Amperage") ?? instantanea,
            tensaoMv: inteiro("Voltage") ?? 0,
            carregando: booleano("IsCharging"),
            naTomada: booleano("ExternalConnected"),
            cheia: booleano("FullyCharged"),
            minutosSistema: tempo.flatMap { $0 > 0 && $0 < 65535 ? $0 : nil }
        )
    }
}

/// Avisa quando o sistema muda algo na fonte de energia (tomada, %, etc.).
final class AvisoEnergia {
    private var fonte: CFRunLoopSource?
    private let aoMudar: () -> Void

    init(aoMudar: @escaping () -> Void) {
        self.aoMudar = aoMudar
        let contexto = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<AvisoEnergia>.fromOpaque(ctx).takeUnretainedValue().aoMudar()
        }, contexto)?.takeRetainedValue() {
            fonte = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
    }

    deinit {
        if let fonte { CFRunLoopRemoveSource(CFRunLoopGetMain(), fonte, .defaultMode) }
    }
}
