import Foundation
import IOKit

/// Leitura e escrita das chaves de ventoinha no AppleSMC. Só funciona como root (o SMC recusa escrita de outros).
/// Chaves: FNum (quantas), F{i}Mn/Mx (limites), F{i}Ac (rotação), F{i}Tg (alvo), F{i}md ou F{i}Md (0 = macOS, 1 = manual).
/// No M3/M4 a troca de modo exige antes Ftst = 1; no M5 não há Ftst (testado num Mac17,6 em 2026-11-16).
final class SMC {
    private var conexao: io_connect_t = 0
    private var infos: [String: (tam: UInt32, tipo: UInt32)] = [:]

    init?() {
        let servico = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard servico != 0 else { return nil }
        defer { IOObjectRelease(servico) }
        guard IOServiceOpen(servico, mach_task_self_, 0, &conexao) == KERN_SUCCESS else { return nil }
    }

    deinit { if conexao != 0 { IOServiceClose(conexao) } }

    private static func quatro(_ s: String) -> UInt32 { s.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) } }
    private static func por(_ v: UInt32, _ off: Int, _ b: inout [UInt8]) { withUnsafeBytes(of: v) { for i in 0..<4 { b[off + i] = $0[i] } } }

    /// Struct SMCKeyData de 80 bytes: chave 0, tamanho 28, tipo 32, resultado 40, comando 42, bytes 48.
    private func chamar(_ e: [UInt8]) -> [UInt8]? {
        var s = [UInt8](repeating: 0, count: 80)
        var t = 80
        let r = e.withUnsafeBytes { eb in
            s.withUnsafeMutableBytes { sb in IOConnectCallStructMethod(conexao, 2, eb.baseAddress, 80, sb.baseAddress, &t) }
        }
        return r == KERN_SUCCESS && s[40] == 0 ? s : nil
    }

    func existe(_ k: String) -> Bool { info(k) != nil }

    private func info(_ k: String) -> (tam: UInt32, tipo: UInt32)? {
        if let i = infos[k] { return i }
        var p = [UInt8](repeating: 0, count: 80)
        Self.por(Self.quatro(k), 0, &p)
        p[42] = 9
        guard let r = chamar(p) else { return nil }
        let i = (r[28..<32].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }, r[32..<36].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        guard i.0 > 0, i.0 <= 32 else { return nil }
        infos[k] = i
        return i
    }

    func ler(_ k: String) -> Double? {
        guard let i = info(k) else { return nil }
        var p = [UInt8](repeating: 0, count: 80)
        Self.por(Self.quatro(k), 0, &p)
        Self.por(i.tam, 28, &p)
        p[42] = 5
        guard let r = chamar(p) else { return nil }
        let b = Array(r[48..<(48 + Int(i.tam))])
        if i.tipo == Self.quatro("flt "), b.count == 4 {
            let v = Double(Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24))
            return v.isFinite ? v : nil
        }
        if b.count == 1 { return Double(b[0]) }
        return nil
    }

    /// Escreve no tipo da chave (flt ou ui8). Devolve se o SMC aceitou.
    @discardableResult
    func escrever(_ k: String, _ v: Double) -> Bool {
        guard let i = info(k) else { return false }
        let bytes: [UInt8]
        if i.tipo == Self.quatro("flt ") {
            bytes = withUnsafeBytes(of: Float(v).bitPattern) { Array($0) }
        } else if i.tam == 1 {
            bytes = [UInt8(max(0, min(255, v)))]
        } else {
            return false
        }
        var p = [UInt8](repeating: 0, count: 80)
        Self.por(Self.quatro(k), 0, &p)
        Self.por(i.tam, 28, &p)
        Self.por(i.tipo, 32, &p)
        p[42] = 6
        for (j, b) in bytes.enumerated() { p[48 + j] = b }
        return chamar(p) != nil
    }
}

/// As ventoinhas do Mac sobre o SMC: dá alvo, devolve ao macOS.
final class ControleSMC {
    private let smc: SMC
    let quantidade: Int
    private var usouFtst = false

    init?() {
        guard let smc = SMC() else { return nil }
        self.smc = smc
        quantidade = max(0, min(8, Int(smc.ler("FNum") ?? 0)))
    }

    private func chaveModo(_ i: Int) -> String? {
        if smc.existe("F\(i)md") { return "F\(i)md" }
        if smc.existe("F\(i)Md") { return "F\(i)Md" }
        return nil
    }

    func limites(_ i: Int) -> (minimo: Double, maximo: Double) {
        (smc.ler("F\(i)Mn") ?? 0, smc.ler("F\(i)Mx") ?? 0)
    }

    /// Põe a ventoinha em manual com o alvo dado. 0 para; acima disso fica entre o mínimo e o máximo dela.
    func definir(_ i: Int, rpm: Double) -> String? {
        guard i < quantidade, let modo = chaveModo(i) else { return "ventoinha \(i) sem chave de modo" }
        let (minimo, maximo) = limites(i)
        guard maximo > 0 else { return "ventoinha \(i) sem máximo" }
        let alvo = rpm <= 0 ? 0 : min(max(rpm, minimo), maximo)
        if smc.ler(modo) != 1 {
            if !smc.escrever(modo, 1) {
                // M3/M4: o firmware só solta a ventoinha depois de Ftst = 1, e leva alguns segundos.
                guard smc.existe("Ftst") else { return "o SMC recusou o modo manual" }
                smc.escrever("Ftst", 1)
                usouFtst = true
                var aceitou = false
                for _ in 0..<60 {
                    usleep(100_000)
                    if smc.escrever(modo, 1), smc.ler(modo) == 1 { aceitou = true; break }
                }
                guard aceitou else { return "o SMC não soltou a ventoinha" }
            }
        }
        if let atual = smc.ler("F\(i)Tg"), abs(atual - alvo) < 1 { return nil }
        return smc.escrever("F\(i)Tg", alvo) ? nil : "o SMC recusou o alvo"
    }

    /// Devolve a ventoinha ao macOS (modo 0).
    func soltar(_ i: Int) {
        guard i < quantidade, let modo = chaveModo(i) else { return }
        if smc.ler(modo) != 0 { smc.escrever(modo, 0) }
    }

    func soltarTodas() {
        for i in 0..<quantidade { soltar(i) }
        if usouFtst || (smc.existe("Ftst") && smc.ler("Ftst") == 1) {
            smc.escrever("Ftst", 0)
            usouFtst = false
        }
    }
}
