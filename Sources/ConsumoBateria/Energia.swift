import Foundation
import IOKit
import IOKit.ps

/// Leituras extras de energia: temperatura, ciclos, carregador e modo de energia.
/// Cada chave que faltar vira nil; nada aqui força unwrap em valor do IOKit.
enum LeitorEnergia {
    static func ler() -> DetalhesEnergia {
        var detalhes = DetalhesEnergia.vazio
        detalhes.poucaEnergia = ProcessInfo.processInfo.isLowPowerModeEnabled
        lerAdaptador(em: &detalhes)

        let servico = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard servico != 0 else { return detalhes }
        defer { IOObjectRelease(servico) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(servico, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return detalhes }
        // Em alguns Macs as chaves só aparecem dentro de BatteryData.
        let dados = dict["BatteryData"] as? [String: Any] ?? [:]

        func inteiro(_ chave: String, em origem: [String: Any]? = nil) -> Int? {
            if let origem { return (origem[chave] as? NSNumber).map { Int($0.int64Value) } }
            if let n = dict[chave] as? NSNumber { return Int(n.int64Value) }
            if let n = dados[chave] as? NSNumber { return Int(n.int64Value) }
            return nil
        }
        func booleano(_ chave: String) -> Bool {
            (dict[chave] as? NSNumber)?.boolValue ?? (dict[chave] as? Bool) ?? false
        }

        // Temperatura em centésimos de °C (3050 = 30,5 °C). Valores absurdos (leitura inválida) viram nil.
        if let t = inteiro("Temperature") ?? inteiro("VirtualTemperature") {
            let graus = Double(t) / 100
            if graus > -20, graus < 120 { detalhes.temperaturaC = graus }
        }
        detalhes.ciclos = inteiro("CycleCount")
        if let fabrica = inteiro("DesignCapacity"), fabrica > 0 { detalhes.capacidadeFabricaMah = fabrica }

        // Entrada do sistema em mW; 0 ou ausente (sem tomada) vira nil.
        let telemetria = dict["PowerTelemetryData"] as? [String: Any]
        if let mw = inteiro("SystemPowerIn", em: telemetria), mw > 0 {
            detalhes.entradaSistemaW = Double(mw) / 1000
        }

        // Heurística de carga otimizada: na tomada, sem carregar e sem estar cheia (a bateria está sendo
        // segurada, por exemplo em 80%), ou o carregador informa um motivo para não carregar
        // (ChargerData/NotChargingReason diferente de 0).
        let naTomada = booleano("ExternalConnected")
        let segurada = naTomada && !booleano("IsCharging") && !booleano("FullyCharged")
        let dadosCarregador = dict["ChargerData"] as? [String: Any]
        let motivo = inteiro("NotChargingReason", em: dadosCarregador) ?? 0
        detalhes.cargaOtimizada = segurada || (naTomada && motivo != 0)

        return detalhes
    }

    private static func lerAdaptador(em detalhes: inout DetalhesEnergia) {
        guard let info = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else { return }
        if let w = info["Watts"] as? NSNumber, w.doubleValue > 0 { detalhes.adaptadorW = w.doubleValue }
        detalhes.adaptadorNome = (info["Name"] as? String) ?? (info["Description"] as? String)
    }
}
