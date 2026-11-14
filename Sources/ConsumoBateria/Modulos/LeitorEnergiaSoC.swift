import Foundation
import IOKit

/// Potência por parte do chip (CPU, GPU, ANE, DRAM) e frequência da GPU, via IOReport (API privada por dlopen/dlsym).
/// Sem root. Se a biblioteca, um grupo ou um canal faltar, o campo fica nil; sem nada, `ler()` devolve nil.
@MainActor
final class LeitorEnergiaSoC {
    private typealias Ponteiro = UnsafeMutableRawPointer
    private typealias FCanais = @convention(c) (CFString, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    private typealias FAssinar = @convention(c) (Ponteiro?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, UInt64, CFTypeRef?) -> Ponteiro?
    private typealias FAmostra = @convention(c) (Ponteiro, CFMutableDictionary?, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias FDelta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias FNome = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias FInteiro = @convention(c) (CFDictionary, Int32) -> Int64
    private typealias FContar = @convention(c) (CFDictionary) -> Int32
    private typealias FNomeEstado = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?
    private typealias FResidencia = @convention(c) (CFDictionary, Int32) -> Int64

    private struct Simbolos {
        var amostra: FAmostra, delta: FDelta, nome: FNome, unidade: FNome, inteiro: FInteiro
        var contar: FContar, nomeEstado: FNomeEstado, residencia: FResidencia
    }

    private var simbolos: Simbolos?
    private var assinatura: Ponteiro?
    private var canais: CFMutableDictionary?
    private var anterior: (amostra: CFDictionary, data: Date)?
    private var frequenciasGPU: [Double] = []   // MHz por estado; índice 0 = desligada, 1 = P1...

    init() {
        guard let lib = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else { return }
        func f<T>(_ n: String, _ t: T.Type) -> T? { dlsym(lib, n).map { unsafeBitCast($0, to: t) } }
        guard let copiar = f("IOReportCopyChannelsInGroup", FCanais.self),
              let assinar = f("IOReportCreateSubscription", FAssinar.self),
              let amostra = f("IOReportCreateSamples", FAmostra.self),
              let delta = f("IOReportCreateSamplesDelta", FDelta.self),
              let nome = f("IOReportChannelGetChannelName", FNome.self),
              let unidade = f("IOReportChannelGetUnitLabel", FNome.self),
              let inteiro = f("IOReportSimpleGetIntegerValue", FInteiro.self),
              let contar = f("IOReportStateGetCount", FContar.self),
              let nomeEstado = f("IOReportStateGetNameForIndex", FNomeEstado.self),
              let residencia = f("IOReportStateGetResidency", FResidencia.self),
              let energia = copiar("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue() else { return }
        // Junta o grupo da GPU (estados de desempenho) aos canais de energia.
        if let gpu = copiar("GPU Stats" as CFString, "GPU Performance States" as CFString, 0, 0, 0)?.takeRetainedValue(),
           let aliasCFunc = f("IOReportMergeChannels", (@convention(c) (CFMutableDictionary, CFMutableDictionary, CFTypeRef?) -> Void).self) {
            aliasCFunc(energia, gpu, nil)
        }
        var inscritos: Unmanaged<CFMutableDictionary>?
        guard let sub = assinar(nil, energia, &inscritos, 0, nil), let inscritos else { return }
        assinatura = sub
        canais = inscritos.takeRetainedValue()
        simbolos = Simbolos(amostra: amostra, delta: delta, nome: nome, unidade: unidade, inteiro: inteiro,
                            contar: contar, nomeEstado: nomeEstado, residencia: residencia)
        frequenciasGPU = Self.lerFrequenciasGPU()
        if let a = amostra(sub, canais, nil)?.takeRetainedValue() { anterior = (a, Date()) }
    }

    func ler() -> EnergiaSoC? {
        guard let s = simbolos, let sub = assinatura, let atual = s.amostra(sub, canais, nil)?.takeRetainedValue() else { return nil }
        let agora = Date()
        defer { anterior = (atual, agora) }
        guard let ant = anterior, let delta = s.delta(ant.amostra, atual, nil)?.takeRetainedValue() else { return nil }
        let dt = agora.timeIntervalSince(ant.data)
        guard dt > 0.2, let lista = (delta as NSDictionary)["IOReportChannels"] as? [NSDictionary] else { return nil }

        var cpu = 0.0, gpu = 0.0, ane = 0.0, dram = 0.0
        var tem = (cpu: false, gpu: false, ane: false, dram: false)
        var gpuMHz: Double?
        var gpuAtivo: Double?
        for c in lista {
            let canal = c as CFDictionary
            guard let nome = s.nome(canal)?.takeUnretainedValue() as String? else { continue }
            if nome == "GPUPH" {
                gpuMHz = frequenciaMedia(canal, s)
                gpuAtivo = residenciaAtiva(canal, s)
                continue
            }
            let w = potencia(canal, s, dt)
            guard let w else { continue }
            if nome.hasSuffix("CPU Energy") { cpu += w; tem.cpu = true }
            else if nome.hasSuffix("GPU Energy") { gpu += w; tem.gpu = true }
            else if nome.hasPrefix("ANE") { ane += w; tem.ane = true }
            else if nome.hasPrefix("DRAM") { dram += w; tem.dram = true }
        }
        var r = EnergiaSoC()
        if tem.cpu { r.cpuW = cpu }
        if tem.gpu { r.gpuW = gpu }
        if tem.ane { r.aneW = ane }
        if tem.dram { r.dramW = dram }
        if let gpuMHz { r.gpuMHz = gpuMHz; r.gpuMaxMHz = frequenciasGPU.max() }
        r.gpuAtivo = gpuAtivo
        return r == EnergiaSoC() ? nil : r
    }

    /// Joules do intervalo / segundos, convertendo pela unidade do canal.
    private func potencia(_ canal: CFDictionary, _ s: Simbolos, _ dt: TimeInterval) -> Double? {
        guard let un = s.unidade(canal)?.takeUnretainedValue() as String? else { return nil }
        let escala: Double
        switch un.trimmingCharacters(in: .whitespaces) {
        case "mJ": escala = 1e-3
        case "uJ", "µJ": escala = 1e-6
        case "nJ": escala = 1e-9
        default: return nil
        }
        let v = Double(s.inteiro(canal, 0)) * escala / dt
        return v.isFinite && v >= 0 && v < 1000 ? v : nil
    }

    /// Média da frequência ponderada pela residência nos estados ligados (P1, P2...); nil se não casar com a tabela.
    private func frequenciaMedia(_ canal: CFDictionary, _ s: Simbolos) -> Double? {
        let n = Int(s.contar(canal))
        guard n > 1, !frequenciasGPU.isEmpty else { return nil }
        var total = 0.0, soma = 0.0
        for i in 0..<n {
            let nome = s.nomeEstado(canal, Int32(i))?.takeUnretainedValue() as String? ?? ""
            let res = Double(s.residencia(canal, Int32(i)))
            if res <= 0 || nome == "OFF" || nome == "IDLE" || nome == "DOWN" { continue }
            // O M5 tem 15 estados P e 14 frequências na tabela: o que passar do fim fica na mais alta.
            guard nome.hasPrefix("P"), let p = Int(nome.dropFirst()), p >= 1 else { return nil }
            soma += res * frequenciasGPU[min(p, frequenciasGPU.count - 1)]; total += res
        }
        return total > 0 ? soma / total : 0
    }

    /// % do tempo do intervalo em algum estado P (GPU ligada).
    private func residenciaAtiva(_ canal: CFDictionary, _ s: Simbolos) -> Double? {
        let n = Int(s.contar(canal))
        guard n > 1 else { return nil }
        var total = 0.0, ativo = 0.0
        for i in 0..<n {
            let nome = s.nomeEstado(canal, Int32(i))?.takeUnretainedValue() as String? ?? ""
            let res = Double(s.residencia(canal, Int32(i)))
            total += res
            if nome.hasPrefix("P") { ativo += res }
        }
        return total > 0 ? min(max(ativo / total * 100, 0), 100) : nil
    }

    /// "voltage-states9" do pmgr: pares (frequência, tensão) de 4 bytes cada; frequência em Hz, entrada 0 = desligada.
    private static func lerFrequenciasGPU() -> [Double] {
        let servico = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("pmgr"))
        guard servico != 0 else { return [] }
        defer { IOObjectRelease(servico) }
        guard let dados = IORegistryEntryCreateCFProperty(servico, "voltage-states9" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
              dados.count >= 8 else { return [] }
        var lista: [Double] = []
        for i in stride(from: 0, to: dados.count - 7, by: 8) {
            let hz = dados.subdata(in: i..<(i + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            let mhz = Double(hz) / (hz > 100_000_000 ? 1e6 : 1e3)
            lista.append(mhz)
        }
        return lista
    }
}
