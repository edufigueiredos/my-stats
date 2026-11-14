import Foundation
import IOKit

/// Volumes, velocidade de leitura/escrita e saúde do SSD. Tudo sem root; toda falha vira nil ou dado ausente.
///
/// Saúde do SSD: o SMART do NVMe interno da Apple (plugin NVMeSMART / AppleANS3) só responde com privilégio de root
/// neste macOS, então `saude` fica nil (ou sem campos) e a temperatura do SSD vem de `LeitorSensores.ssdC`.
@MainActor
final class LeitorDisco {
    private var anterior: (leitura: UInt64, escrita: UInt64, data: Date)?
    private var protocolos: [String: String?] = [:]

    init() {}

    func ler() -> LeituraDisco? {
        let volumes = lerVolumes()
        guard !volumes.isEmpty else { return nil }
        var leitura = LeituraDisco(volumes: volumes)
        if let (lidos, gravados) = Self.somarEstatisticas() {
            let agora = Date()
            if let ant = anterior {
                let dt = agora.timeIntervalSince(ant.data)
                if dt > 0.2 {
                    // Contador que diminui (disco removido) conta como 0 neste intervalo.
                    leitura.leituraBps = lidos >= ant.leitura ? Double(lidos - ant.leitura) / dt : 0
                    leitura.escritaBps = gravados >= ant.escrita ? Double(gravados - ant.escrita) / dt : 0
                }
            }
            anterior = (lidos, gravados, agora)
        }
        return leitura
    }

    // MARK: Volumes

    private func lerVolumes() -> [VolumeDisco] {
        let chaves: [URLResourceKey] = [
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsInternalKey, .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeLocalizedFormatDescriptionKey,
            .volumeLocalizedNameKey, .volumeIsBrowsableKey, .volumeIsLocalKey, .volumeUUIDStringKey,
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: chaves, options: [.skipHiddenVolumes]) else { return [] }
        var vistos = Set<String>()
        var lista: [VolumeDisco] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(chaves)) else { continue }
            let raiz = url.path == "/"
            if v.volumeIsLocal == false { continue }
            if !raiz && (v.volumeIsBrowsable == false || !url.path.hasPrefix("/Volumes/")) { continue }
            guard let total = v.volumeTotalCapacity, total > 0 else { continue }
            let chave = v.volumeUUIDString ?? url.path
            guard vistos.insert(chave).inserted else { continue }

            let importante = v.volumeAvailableCapacityForImportantUsage.map { Int64($0) } ?? Int64(v.volumeAvailableCapacity ?? 0)
            let comum = Int64(v.volumeAvailableCapacity ?? Int(importante))
            let livre = max(importante, 0)
            let purgavel = max(importante - comum, 0)
            let interno = v.volumeIsInternal ?? raiz
            let ejetavel = (v.volumeIsEjectable ?? false) || (v.volumeIsRemovable ?? false)
            let formato = Self.formatoCurto(v.volumeLocalizedFormatDescription)
            let nome = v.volumeLocalizedName ?? url.lastPathComponent

            lista.append(VolumeDisco(
                id: url.path, nome: raiz ? (v.volumeLocalizedName ?? "Macintosh HD") : nome,
                tipo: tipo(url: url, interno: interno, formato: formato),
                url: url, totalBytes: UInt64(total), livreBytes: UInt64(livre), purgavelBytes: UInt64(purgavel),
                interno: interno, ejetavel: ejetavel))
        }
        // Interno primeiro, depois por nome.
        return lista.sorted { ($0.interno ? 0 : 1, $0.nome) < ($1.interno ? 0 : 1, $1.nome) }
    }

    /// "APFS (Diferenciar maiúsculas)" vira "APFS".
    private static func formatoCurto(_ descricao: String?) -> String? {
        guard let d = descricao, !d.isEmpty else { return nil }
        if let i = d.firstIndex(of: "(") , d.hasPrefix("MS-DOS") { return String(d[d.index(after: i)...].dropLast()) }
        if let i = d.firstIndex(of: "(") { return d[..<i].trimmingCharacters(in: .whitespaces) }
        return d
    }

    private func tipo(url: URL, interno: Bool, formato: String?) -> String {
        let protocolo = protocoloFisico(url: url)
        let base: String
        if interno {
            switch protocolo {
            case "Secure Digital": base = "Cartão SD"
            default: base = "SSD interno"
            }
        } else {
            switch protocolo {
            case "USB": base = "USB"
            case "Thunderbolt": base = "Thunderbolt"
            case "Secure Digital": base = "Cartão SD"
            case "Virtual Interface": base = "Imagem de disco"
            case .some(let p) where !p.isEmpty: base = p
            default: base = "Externo"
            }
        }
        return formato.map { "\(base) · \($0)" } ?? base
    }

    /// "Physical Interconnect" do dispositivo que sustenta o volume (sobe pelo IORegistry a partir do nome BSD).
    private func protocoloFisico(url: URL) -> String? {
        var fs = statfs()
        guard statfs(url.path, &fs) == 0 else { return nil }
        let origem = withUnsafePointer(to: &fs.f_mntfromname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        guard origem.hasPrefix("/dev/") else { return nil }
        let bsd = String(origem.dropFirst(5))
        if let guardado = protocolos[bsd] { return guardado }
        var resultado: String?
        let entrada = IOServiceGetMatchingService(kIOMainPortDefault, IOBSDNameMatching(kIOMainPortDefault, 0, bsd))
        if entrada != 0 {
            defer { IOObjectRelease(entrada) }
            let opcoes = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
            if let p = IORegistryEntrySearchCFProperty(entrada, kIOServicePlane, "Protocol Characteristics" as CFString, kCFAllocatorDefault, opcoes) as? [String: Any] {
                resultado = p["Physical Interconnect"] as? String
            }
        }
        protocolos[bsd] = resultado
        return resultado
    }

    // MARK: Velocidade

    /// Soma bytes lidos e gravados de todos os IOBlockStorageDriver.
    private static func somarEstatisticas() -> (UInt64, UInt64)? {
        var iterador: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterador) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterador) }
        var lidos: UInt64 = 0, gravados: UInt64 = 0
        var achou = false
        while case let servico = IOIteratorNext(iterador), servico != 0 {
            defer { IOObjectRelease(servico) }
            guard let est = IORegistryEntryCreateCFProperty(servico, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] else { continue }
            achou = true
            lidos &+= (est["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            gravados &+= (est["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return achou ? (lidos, gravados) : nil
    }
}
