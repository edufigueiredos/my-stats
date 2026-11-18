import Foundation

// Ajustes do controle das ventoinhas (desenho: docs/desenho/modulos, artboards VentoinhasPainel e PreferenciasVentoinhas).
// % é sempre da rotação máxima de cada ventoinha, como no resto do app.

enum ModoVentoinhas: String, Codable, CaseIterable, Sendable {
    case automatico, manual, curva

    var titulo: String {
        switch self {
        case .automatico: return "Automático"
        case .manual: return "Manual"
        case .curva: return "Curva"
        }
    }
}

enum ReferenciaTemperatura: String, Codable, CaseIterable, Sendable {
    case maisQuente, cpu, gpu

    var titulo: String {
        switch self {
        case .maisQuente: return "A mais quente"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        }
    }
}

struct PontoCurva: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    /// °C, de 30 a 100.
    var temp: Double
    /// % da rotação máxima, de 0 a 100. 0 = deixa com o macOS (que para a ventoinha quando o Mac está frio).
    var pct: Double

    static let tempMin: Double = 30, tempMax: Double = 100

    private enum CodingKeys: String, CodingKey { case temp, pct }
    init(_ temp: Double, _ pct: Double) { self.temp = temp; self.pct = pct }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        temp = try c.decode(Double.self, forKey: .temp)
        pct = try c.decode(Double.self, forKey: .pct)
    }
}

enum PerfilCurva: String, Codable, CaseIterable, Sendable {
    case silencioso, equilibrado, desempenho, maximo, meu

    var titulo: String {
        switch self {
        case .silencioso: return "Silencioso"
        case .equilibrado: return "Equilibrado"
        case .desempenho: return "Desempenho"
        case .maximo: return "Máximo"
        case .meu: return "Meu perfil"
        }
    }

    /// Pontos do perfil pronto (nil no Meu perfil, que é o que o usuário desenhou). Guardados uma vez só: os ids
    /// precisam ser os mesmos entre um desenho e outro para o arraste achar o ponto.
    var pontos: [PontoCurva]? {
        switch self {
        case .silencioso: return Self.pontosSilencioso
        case .equilibrado: return Self.pontosEquilibrado
        case .desempenho: return Self.pontosDesempenho
        case .maximo: return Self.pontosMaximo
        case .meu: return nil
        }
    }

    private static let pontosSilencioso = [PontoCurva(50, 0), PontoCurva(65, 25), PontoCurva(80, 50), PontoCurva(90, 80), PontoCurva(95, 100)]
    private static let pontosEquilibrado = [PontoCurva(45, 0), PontoCurva(55, 30), PontoCurva(70, 50), PontoCurva(85, 80), PontoCurva(95, 100)]
    private static let pontosDesempenho = [PontoCurva(40, 30), PontoCurva(55, 50), PontoCurva(70, 75), PontoCurva(85, 100)]
    private static let pontosMaximo = [PontoCurva(30, 100)]
}

struct AjustesVentoinhas: Codable, Sendable, Equatable {
    var modo: ModoVentoinhas = .automatico
    /// Manual: % das duas juntas, ou de cada uma quando `separadas`.
    var manualPct: Double = 60
    var separadas = false
    var manualPorVentoinha: [Double] = [60, 60]
    var referencia: ReferenciaTemperatura = .maisQuente
    var perfil: PerfilCurva = .equilibrado
    /// Pontos do Meu perfil.
    var meuPerfil: [PontoCurva] = PerfilCurva.equilibrado.pontos ?? []
    /// Acima disto (°C), as ventoinhas vão ao máximo em qualquer modo.
    var limite: Double = 95
    /// Ao abrir o app (por exemplo depois de reiniciar o Mac), volta ao modo escolhido; desligado, abre no Automático.
    var reaplicar = true

    static let limiteMin: Double = 70, limiteMax: Double = 105

    var curva: [PontoCurva] { (perfil.pontos ?? meuPerfil).sorted { $0.temp < $1.temp } }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case modo, manualPct, separadas, manualPorVentoinha, referencia, perfil, meuPerfil, limite, reaplicar
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let p = AjustesVentoinhas()
        modo = (try? c.decodeIfPresent(ModoVentoinhas.self, forKey: .modo)) ?? p.modo
        manualPct = (try? c.decodeIfPresent(Double.self, forKey: .manualPct)) ?? p.manualPct
        separadas = (try? c.decodeIfPresent(Bool.self, forKey: .separadas)) ?? p.separadas
        manualPorVentoinha = (try? c.decodeIfPresent([Double].self, forKey: .manualPorVentoinha)) ?? p.manualPorVentoinha
        referencia = (try? c.decodeIfPresent(ReferenciaTemperatura.self, forKey: .referencia)) ?? p.referencia
        perfil = (try? c.decodeIfPresent(PerfilCurva.self, forKey: .perfil)) ?? p.perfil
        meuPerfil = (try? c.decodeIfPresent([PontoCurva].self, forKey: .meuPerfil)) ?? p.meuPerfil
        limite = (try? c.decodeIfPresent(Double.self, forKey: .limite)) ?? p.limite
        reaplicar = (try? c.decodeIfPresent(Bool.self, forKey: .reaplicar)) ?? p.reaplicar
        saneiar()
    }

    mutating func saneiar() {
        func lim(_ v: Double, _ a: Double, _ b: Double) -> Double { v.isFinite ? min(max(v, a), b) : a }
        manualPct = lim(manualPct, 0, 100)
        manualPorVentoinha = manualPorVentoinha.prefix(8).map { lim($0, 0, 100) }
        limite = lim(limite, Self.limiteMin, Self.limiteMax)
        meuPerfil = meuPerfil.prefix(12).map { PontoCurva(lim($0.temp, PontoCurva.tempMin, PontoCurva.tempMax), lim($0.pct, 0, 100)) }
        if meuPerfil.isEmpty { meuPerfil = PerfilCurva.equilibrado.pontos ?? [] }
    }

    /// % da curva para a temperatura: interpolação linear; fora dos pontos, vale o ponto da ponta.
    static func pct(curva: [PontoCurva], temp: Double) -> Double {
        let pts = curva.sorted { $0.temp < $1.temp }
        guard let primeiro = pts.first, let ultimo = pts.last else { return 0 }
        if temp <= primeiro.temp { return primeiro.pct }
        if temp >= ultimo.temp { return ultimo.pct }
        for (a, b) in zip(pts, pts.dropFirst()) where temp <= b.temp {
            let f = b.temp == a.temp ? 1 : (temp - a.temp) / (b.temp - a.temp)
            return a.pct + (b.pct - a.pct) * f
        }
        return ultimo.pct
    }
}
