import Foundation
import IOKit

/// Temperaturas (IOHIDEventSystemClient, API privada por dlsym) e ventoinhas/potência (SMC). Sem root.
/// Qualquer símbolo ou chave ausente vira nil; nunca derruba o app.
@MainActor
final class LeitorSensores {
    private typealias Ponteiro = UnsafeMutableRawPointer
    private typealias FCriar = @convention(c) (CFAllocator?) -> Ponteiro?
    private typealias FFiltrar = @convention(c) (Ponteiro, CFDictionary) -> Int32
    private typealias FServicos = @convention(c) (Ponteiro) -> Unmanaged<CFArray>?
    private typealias FPropriedade = @convention(c) (Ponteiro, CFString) -> Unmanaged<CFTypeRef>?
    private typealias FEvento = @convention(c) (Ponteiro, Int64, Int32, Int64) -> Ponteiro?
    private typealias FValor = @convention(c) (Ponteiro, Int32) -> Double

    private struct Sensor { var nome: String; var servico: Ponteiro }

    private let copiarEvento: FEvento?
    private let valorFloat: FValor?
    private var sensores: [Sensor] = []
    private var cliente: Ponteiro?
    private var servicos: CFArray?
    private let smc = ConexaoSMC()
    private var numVentoinhas: Int?

    init() {
        let lib = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        func simbolo<T>(_ nome: String, _ tipo: T.Type) -> T? {
            guard let lib, let p = dlsym(lib, nome) else { return nil }
            return unsafeBitCast(p, to: tipo)
        }
        let criar = simbolo("IOHIDEventSystemClientCreate", FCriar.self)
        let filtrar = simbolo("IOHIDEventSystemClientSetMatching", FFiltrar.self)
        let listar = simbolo("IOHIDEventSystemClientCopyServices", FServicos.self)
        let propriedade = simbolo("IOHIDServiceClientCopyProperty", FPropriedade.self)
        copiarEvento = simbolo("IOHIDServiceClientCopyEvent", FEvento.self)
        valorFloat = simbolo("IOHIDEventGetFloatValue", FValor.self)

        guard let criar, let filtrar, let listar, let propriedade, copiarEvento != nil, valorFloat != nil,
              let c = criar(kCFAllocatorDefault) else { return }
        cliente = c
        _ = filtrar(c, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        guard let lista = listar(c)?.takeRetainedValue() else { return }
        servicos = lista
        for i in 0..<CFArrayGetCount(lista) {
            guard let s = CFArrayGetValueAtIndex(lista, i) else { continue }
            let servico = UnsafeMutableRawPointer(mutating: s)
            if let nome = propriedade(servico, "Product" as CFString)?.takeRetainedValue() as? String {
                sensores.append(Sensor(nome: nome, servico: servico))
            }
        }
    }

    func ler(entradaSistemaW: Double?, carregadorW: Double?) -> LeituraSensores? {
        var r = LeituraSensores()
        var temps: [(String, Double)] = []
        if let copiarEvento, let valorFloat {
            for s in sensores {
                guard let evento = copiarEvento(s.servico, 15, 0, 0) else { continue }
                defer { Unmanaged<CFTypeRef>.fromOpaque(evento).release() }
                let v = valorFloat(evento, 15 << 16)
                if v > 0, v <= 130, v.isFinite { temps.append((s.nome, v)) }
            }
        }
        func media(_ prefixos: [String]) -> Double? {
            let v = temps.filter { t in prefixos.contains { t.0.hasPrefix($0) } }.map(\.1)
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }
        r.cpuC = media(["pACC MTR Temp Sensor", "eACC MTR Temp Sensor"]) ?? media(["PMU tdie"]) ?? media(["PMU TP"])
        r.gpuC = media(["GPU MTR Temp Sensor"])
        r.ssdC = media(["NAND CH0 temp"])
        r.bateriaC = media(["gas gauge battery"])
        // Memória e ar interno: o chip não expõe um sensor claramente identificável por nome; ficam nil.
        // Vários serviços repetem o mesmo nome (um por sensor físico): vira uma linha com a média.
        let porNome = Dictionary(grouping: temps, by: \.0).mapValues { $0.map(\.1).reduce(0, +) / Double($0.count) }
        r.todas = porNome.sorted { $0.key < $1.key }.map { Temperatura(id: $0.key, nome: $0.key, valorC: $0.value) }

        r.ventoinhas = lerVentoinhas()
        if let w = smc.ler("PSTR"), w > 0, w < 1000 { r.sistemaW = w } else { r.sistemaW = entradaSistemaW }
        if let w = smc.ler("PDTR"), w >= 0, w < 200 { r.telaW = w }
        r.carregadorW = carregadorW
        let vazio = r.cpuC == nil && r.gpuC == nil && r.todas.isEmpty && r.ventoinhas.isEmpty && r.sistemaW == nil
        return vazio ? nil : r
    }

    private func lerVentoinhas() -> [Ventoinha] {
        if numVentoinhas == nil { numVentoinhas = Int(smc.ler("FNum") ?? 0) }
        guard let n = numVentoinhas, n > 0, n <= 8 else { return [] }
        var lista: [Ventoinha] = []
        for i in 0..<n {
            guard let rpm = smc.ler("F\(i)Ac") else { continue }
            let nome = n == 1 ? "Ventoinha" : (n == 2 ? (i == 0 ? "Esquerda" : "Direita") : "Ventoinha \(i + 1)")
            lista.append(Ventoinha(id: i, nome: nome, rpm: max(rpm, 0), minimoRpm: smc.ler("F\(i)Mn"), maximoRpm: smc.ler("F\(i)Mx")))
        }
        return lista
    }
}

/// Conexão com o AppleSMC. Fecha no deinit; não guarda estado mutável além do handle.
private final class ConexaoSMC: @unchecked Sendable {
    private var conexao: io_connect_t = 0

    init() {
        let servico = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard servico != 0 else { return }
        defer { IOObjectRelease(servico) }
        var c: io_connect_t = 0
        if IOServiceOpen(servico, mach_task_self_, 0, &c) == KERN_SUCCESS { conexao = c }
    }

    deinit { if conexao != 0 { IOServiceClose(conexao) } }

    private static func quatro(_ s: String) -> UInt32 { s.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) } }

    /// Struct SMCKeyData de 80 bytes, montada por deslocamento: chave 0, tamanho 28, tipo 32, comando 42, bytes 48.
    private func chamar(_ entrada: [UInt8]) -> [UInt8]? {
        var saida = [UInt8](repeating: 0, count: 80)
        var tamanho = 80
        let r = entrada.withUnsafeBytes { e in
            saida.withUnsafeMutableBytes { s in
                IOConnectCallStructMethod(conexao, 2, e.baseAddress, 80, s.baseAddress, &tamanho)
            }
        }
        return r == KERN_SUCCESS && saida[40] == 0 ? saida : nil
    }

    func ler(_ chave: String) -> Double? {
        guard conexao != 0 else { return nil }
        var info = [UInt8](repeating: 0, count: 80)
        func gravar(_ v: UInt32, _ off: Int, em b: inout [UInt8]) { withUnsafeBytes(of: v) { for i in 0..<4 { b[off + i] = $0[i] } } }
        gravar(Self.quatro(chave), 0, em: &info)
        info[42] = 9 // ler informação da chave
        guard let resp = chamar(info) else { return nil }
        let tam = resp[28..<32].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let tipo = resp[32..<36].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        guard tam > 0, tam <= 32 else { return nil }
        var pedido = [UInt8](repeating: 0, count: 80)
        gravar(Self.quatro(chave), 0, em: &pedido)
        gravar(tam, 28, em: &pedido)
        pedido[42] = 5 // ler bytes
        guard let dados = chamar(pedido) else { return nil }
        let b = Array(dados[48..<(48 + Int(tam))])
        switch tipo {
        case Self.quatro("flt "):
            guard b.count == 4 else { return nil }
            let v = Double(Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24))
            return v.isFinite ? v : nil
        case Self.quatro("fpe2"):
            guard b.count == 2 else { return nil }
            return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4
        case Self.quatro("ui8 "): return Double(b[0])
        case Self.quatro("ui16"): return b.count == 2 ? Double(UInt16(b[0]) << 8 | UInt16(b[1])) : nil
        case Self.quatro("ui32"): return b.count == 4 ? Double(b.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }) : nil
        default: return nil
        }
    }
}
