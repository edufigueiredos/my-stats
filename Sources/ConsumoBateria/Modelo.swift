import Foundation

// MARK: - Estados, peças e formatos da barra

/// Os cinco estados que a barra de menus distingue; cada um tem a sua lista de peças e a sua cor.
enum EstadoBarra: String, CaseIterable, Codable, Sendable, Identifiable {
    case cheia, carregando, descarregando, parado, alto

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .cheia: return "Cheia"
        case .carregando: return "Carregando"
        case .descarregando: return "Descarregando"
        case .parado: return "Na tomada, parado"
        case .alto: return "Consumo alto"
        }
    }

    /// Frase curta do desenho (Preferencias.dc.html) sob o nome do estado.
    var dica: String {
        switch self {
        case .cheia: return "na tomada, 100%"
        case .carregando: return "entrando energia"
        case .descarregando: return "na bateria"
        case .parado: return "carga otimizada"
        case .alto: return "acima do aviso"
        }
    }

    var corPadraoHex: String {
        switch self {
        case .cheia: return "#34C759"
        case .carregando: return "#E0B357"
        case .descarregando: return "#FFFFFF"
        case .parado: return "#BF5AF2"
        case .alto: return "#FF9F0A"
        }
    }
}

/// As 15 peças que se combinam na barra, na ordem da paleta do desenho.
enum Peca: String, CaseIterable, Codable, Sendable, Identifiable {
    case ritmo, ritmoWatts, ritmoSobreBateria, tempoSobreBateria, porcentagem, tempo, watts
    case etiquetaValor, icone, bateria, barraVertical, anel, velocimetro, numeroPilula, espacador

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .ritmo: return "Ritmo %/h"
        case .ritmoWatts: return "Ritmo e watts"
        case .ritmoSobreBateria: return "Ritmo sobre a bateria"
        case .tempoSobreBateria: return "Tempo sobre a bateria"
        case .porcentagem: return "Porcentagem"
        case .tempo: return "Tempo"
        case .watts: return "Watts"
        case .etiquetaValor: return "Etiqueta e valor"
        case .icone: return "Ícone"
        case .bateria: return "Bateria"
        case .barraVertical: return "Barra vertical"
        case .anel: return "Anel"
        case .velocimetro: return "Velocímetro"
        case .numeroPilula: return "Número na pílula"
        case .espacador: return "Espaçador"
        }
    }

    /// Nome de SF Symbol para a paleta de peças.
    var simbolo: String {
        switch self {
        case .ritmo: return "gauge.with.dots.needle.33percent"
        case .ritmoWatts: return "text.justify.leading"
        case .ritmoSobreBateria: return "battery.50percent"
        case .tempoSobreBateria: return "clock.badge"
        case .porcentagem: return "percent"
        case .tempo: return "clock"
        case .watts: return "bolt"
        case .etiquetaValor: return "tag"
        case .icone: return "arrow.down.circle"
        case .bateria: return "battery.75percent"
        case .barraVertical: return "chart.bar.fill"
        case .anel: return "circle.dotted"
        case .velocimetro: return "gauge.with.needle"
        case .numeroPilula: return "capsule"
        case .espacador: return "arrow.left.and.right"
        }
    }
}

/// Os formatos prontos do item da barra; cada um é uma predefinição das listas de peças.
enum FormatoBarra: String, CaseIterable, Codable, Sendable, Identifiable {
    case empilhado, icone, valor, iconeValor, duasLinhas, velocimetro

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .empilhado: return "Empilhado"
        case .icone: return "Ícone"
        case .valor: return "Valor"
        case .iconeValor: return "Ícone + valor"
        case .duasLinhas: return "Duas linhas"
        case .velocimetro: return "Velocímetro"
        }
    }

    var descricao: String {
        switch self {
        case .empilhado: return "Igual ao seu iStat: valor grande, tempo pequeno em cima da bateria. Monte o seu nas preferências."
        case .icone: return "A bateria enche com o %; seta, raio ou tomada dizem o que está acontecendo."
        case .valor: return "Só o ritmo em %/h, sem desenho."
        case .iconeValor: return "Bateria e ritmo lado a lado."
        case .duasLinhas: return "Ritmo em cima; watts e tempo embaixo, como o iStat."
        case .velocimetro: return "O ponteiro sobe conforme o gasto; carregando vira raio."
        }
    }

    /// Lista de peças do formato em cada estado.
    /// Parado e cheia não têm ritmo: o Empilhado mostra "80%" e "tomada" (peça Tempo sobre a bateria).
    func pecas(para estado: EstadoBarra) -> [Peca] {
        let semRitmo = estado == .parado || estado == .cheia
        switch self {
        case .empilhado: return semRitmo ? [.porcentagem, .tempoSobreBateria] : [.ritmo, .tempoSobreBateria]
        case .icone: return [.bateria]
        case .valor: return semRitmo ? [.porcentagem] : [.ritmo]
        case .iconeValor: return semRitmo ? [.bateria, .porcentagem] : [.bateria, .ritmo]
        case .duasLinhas: return [.ritmoWatts]
        case .velocimetro: return [.velocimetro, semRitmo ? .porcentagem : .ritmo]
        }
    }
}

/// Peças e cor de um estado.
struct ConfigEstado: Codable, Sendable, Equatable {
    var pecas: [Peca]
    var corHex: String
}

// MARK: - Preferências em forma de tipo

enum MediaRitmo: String, CaseIterable, Codable, Sendable {
    case agora, cincoMin, quinzeMin, umaHora

    var segundos: TimeInterval {
        switch self {
        case .agora: return 0
        case .cincoMin: return 5 * 60
        case .quinzeMin: return 15 * 60
        case .umaHora: return 60 * 60
        }
    }

    var titulo: String {
        switch self {
        case .agora: return "Agora"
        case .cincoMin: return "5 min"
        case .quinzeMin: return "15 min"
        case .umaHora: return "1 h"
        }
    }
}

enum SentidoRitmo: String, CaseIterable, Codable, Sendable {
    case sinais, setas, soCor

    var titulo: String {
        switch self {
        case .sinais: return "− e +"
        case .setas: return "Setas"
        case .soCor: return "Só cor"
        }
    }
}

// MARK: - Dados lidos

/// O que vem além da leitura básica da bateria (temperatura, ciclos, carregador, modo de energia).
struct DetalhesEnergia: Sendable, Equatable {
    var temperaturaC: Double?
    var ciclos: Int?
    var capacidadeFabricaMah: Int?
    /// Potência máxima do carregador, em W.
    var adaptadorW: Double?
    var adaptadorNome: String?
    /// PowerTelemetryData/SystemPowerIn: tudo o que entra pelo carregador, em W.
    var entradaSistemaW: Double?
    var cargaOtimizada: Bool
    var poucaEnergia: Bool

    static let vazio = DetalhesEnergia(
        temperaturaC: nil, ciclos: nil, capacidadeFabricaMah: nil, adaptadorW: nil,
        adaptadorNome: nil, entradaSistemaW: nil, cargaOtimizada: false, poucaEnergia: false)
}

/// Gasto estimado de um app (nunca medido: o macOS não dá energia por app sem privilégio).
struct ConsumoApp: Sendable, Identifiable, Equatable {
    /// Bundle id ou nome.
    var id: String
    var nome: String
    /// Estimativa, em W.
    var watts: Double
    /// 0...1, relativa ao app que mais gasta na lista.
    var fracao: Double
}

/// Um ponto do histórico, agregado por minuto.
struct PontoMinuto: Codable, Sendable, Equatable {
    var data: Date
    var percentual: Double
    /// %/h; negativo saindo.
    var ritmo: Double
    /// Negativo saindo da bateria.
    var watts: Double
    var naTomada: Bool
    var carregando: Bool
}

// MARK: - Situação

/// Tudo o que a barra e o painel desenham num instante.
struct Situacao: Sendable {
    var leitura: LeituraBateria
    var estado: EstadoBarra
    var ritmoMedio: Double?
    var ritmoAgora: Double
    var ritmoUltimaHora: Double?
    /// Minutos até vazia (descarregando) ou até cheia (carregando).
    var minutosAteFim: Double?
    var minutosAte80: Double?
    var detalhes: DetalhesEnergia
    var apps: [ConsumoApp]
    /// Últimas 24 h, um ponto por minuto.
    var serie: [PontoMinuto]

    /// Horário previsto para acabar ou encher.
    var horarioFim: Date? {
        minutosAteFim.map { leitura.data.addingTimeInterval($0 * 60) }
    }

    var horarioAte80: Date? {
        minutosAte80.map { leitura.data.addingTimeInterval($0 * 60) }
    }

    /// Capacidade atual sobre a de fábrica, em 0...100 (pode passar de 100); nil sem o dado de fábrica.
    var saudePercentual: Double? {
        guard let fab = detalhes.capacidadeFabricaMah, fab > 0, leitura.capacidadeMah > 0 else { return nil }
        return Double(leitura.capacidadeMah) / Double(fab) * 100
    }

    /// Carregando: quanto da entrada vai para a bateria (V x I), em W.
    var paraBateriaW: Double? {
        guard leitura.carregando, leitura.tensaoMv > 0, leitura.correnteMa > 0 else { return nil }
        return leitura.watts
    }

    /// Carregando: quanto da entrada fica com o Mac (entrada do sistema menos a bateria), em W.
    var paraMacW: Double? {
        guard let entrada = detalhes.entradaSistemaW, let bateria = paraBateriaW else { return nil }
        return max(0, entrada - bateria)
    }

    /// Cheia se cheia; carregando se carregando; parado se na tomada sem carregar;
    /// alto se o ritmo for menor que −limite; senão descarregando.
    static func estado(de leitura: LeituraBateria, ritmo: Double?, limiteAlto: Double) -> EstadoBarra {
        if leitura.cheia { return .cheia }
        if leitura.carregando { return .carregando }
        if leitura.naTomada { return .parado }
        if let ritmo, ritmo < -limiteAlto { return .alto }
        return .descarregando
    }
}

// MARK: - Exemplos (só para o modo --foto)

extension Situacao {
    private static func leituraExemplo(percentual: Int, capacidade: Int, correnteMa: Int, tensaoMv: Int,
                                       carregando: Bool, naTomada: Bool, cheia: Bool) -> LeituraBateria {
        LeituraBateria(
            data: Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date()) ?? Date(), percentual: percentual, cargaMah: capacidade * percentual / 100,
            capacidadeMah: capacidade, correnteMa: correnteMa, correnteMediaMa: correnteMa,
            tensaoMv: tensaoMv, carregando: carregando, naTomada: naTomada, cheia: cheia,
            minutosSistema: nil)
    }

    /// Série sintética de 24 h, montada de trás para frente a partir do % atual.
    /// `ritmoEm(k)` dá (ritmo, naTomada, carregando) k minutos atrás; ao chegar em 100% o resto é tomada parada.
    private static func serieSintetica(fim: Date, percentualAtual: Double, capacidadeMah: Int, tensaoMv: Int,
                                       ritmoEm: (Int) -> (Double, Bool, Bool)) -> [PontoMinuto] {
        var pontos: [PontoMinuto] = []
        pontos.reserveCapacity(1440)
        var pct = percentualAtual
        var cheiaDaquiPraTras = false
        let wPorRitmo = Double(capacidadeMah) * Double(tensaoMv) / 1e8   // W por 1 %/h
        for k in 0..<1440 {
            var (ritmo, tomada, carregando) = ritmoEm(k)
            if cheiaDaquiPraTras { (ritmo, tomada, carregando) = (0, true, false); pct = 100 }
            let watts = cheiaDaquiPraTras ? 3.2 : ritmo * wPorRitmo
            pontos.append(PontoMinuto(data: fim.addingTimeInterval(-Double(k) * 60), percentual: pct,
                                      ritmo: ritmo, watts: watts, naTomada: tomada, carregando: carregando))
            pct -= ritmo / 60
            if pct >= 100 { pct = 100; cheiaDaquiPraTras = true }
            pct = max(0, pct)
        }
        return pontos.reversed()
    }

    static var exemploDescarregando: Situacao {
        let leitura = leituraExemplo(percentual: 54, capacidade: 6000, correnteMa: -924, tensaoMv: 11600,
                                     carregando: false, naTomada: false, cheia: false)
        let serie = serieSintetica(fim: leitura.data, percentualAtual: 54, capacidadeMah: 6000, tensaoMv: 11600) { k in
            let ritmo = -(10.5 + 3.5 * sin(Double(k) / 17) + 1.5 * sin(Double(k) / 5))
            return (ritmo, false, false)
        }
        let apps = [
            ConsumoApp(id: "claude", nome: "Claude", watts: 3.1, fracao: 3.1 / 3.3),
            ConsumoApp(id: "chrome", nome: "Google Chrome", watts: 2.4, fracao: 2.4 / 3.3),
            ConsumoApp(id: "teams", nome: "Microsoft Teams", watts: 1.9, fracao: 1.9 / 3.3),
            ConsumoApp(id: "sistema", nome: "Tela e sistema", watts: 3.3, fracao: 1),
        ]
        let detalhes = DetalhesEnergia(
            temperaturaC: 27, ciclos: 37, capacidadeFabricaMah: 6000, adaptadorW: nil, adaptadorNome: nil,
            entradaSistemaW: nil, cargaOtimizada: false, poucaEnergia: true)
        return Situacao(leitura: leitura, estado: .descarregando, ritmoMedio: -11.3, ritmoAgora: -15.4,
                        ritmoUltimaHora: -10.8, minutosAteFim: 286, minutosAte80: nil,
                        detalhes: detalhes, apps: apps, serie: serie)
    }

    /// Números de PainelCarregando.dc.html. O desenho tem "+4.480 mA" e "Bateria 52 W" que não fecham com
    /// 12,6 V; aqui vale a divisão de potência (52 W para a bateria + 12 W para o Mac = 64 W).
    static var exemploCarregando: Situacao {
        let leitura = leituraExemplo(percentual: 54, capacidade: 10100, correnteMa: 4130, tensaoMv: 12600,
                                     carregando: true, naTomada: true, cheia: false)
        let serie = serieSintetica(fim: leitura.data, percentualAtual: 54, capacidadeMah: 10100, tensaoMv: 12600) { k in
            if k < 40 { return (38 + 3 * sin(Double(k) / 6), true, true) }   // ligou há 40 min
            return (-(10.5 + 3.5 * sin(Double(k) / 17) + 1.5 * sin(Double(k) / 5)), false, false)
        }
        let detalhes = DetalhesEnergia(
            temperaturaC: 31, ciclos: 37, capacidadeFabricaMah: 10100, adaptadorW: 96,
            adaptadorNome: "Carregador USB-C de 96 W", entradaSistemaW: 64, cargaOtimizada: true, poucaEnergia: false)
        return Situacao(leitura: leitura, estado: .carregando, ritmoMedio: 38, ritmoAgora: 41,
                        ritmoUltimaHora: nil, minutosAteFim: 72, minutosAte80: 41,
                        detalhes: detalhes, apps: [], serie: serie)
    }

    /// Números de Main.dc.html para cada estado.
    static func exemplo(_ estado: EstadoBarra) -> Situacao {
        switch estado {
        case .descarregando:
            return exemploDescarregando
        case .carregando:
            return exemploCarregando
        case .parado:
            let leitura = leituraExemplo(percentual: 80, capacidade: 6000, correnteMa: 0, tensaoMv: 12400,
                                         carregando: false, naTomada: true, cheia: false)
            var s = exemploDescarregando
            s.leitura = leitura
            s.estado = .parado
            s.ritmoMedio = 0; s.ritmoAgora = 0; s.ritmoUltimaHora = nil
            s.minutosAteFim = nil; s.minutosAte80 = nil
            s.detalhes.cargaOtimizada = true; s.detalhes.poucaEnergia = false
            s.apps = []
            return s
        case .alto:
            let leitura = leituraExemplo(percentual: 31, capacidade: 6000, correnteMa: -1966, tensaoMv: 11600,
                                         carregando: false, naTomada: false, cheia: false)
            var s = exemploDescarregando
            s.leitura = leitura
            s.estado = .alto
            s.ritmoMedio = -24.6; s.ritmoAgora = -32.8; s.ritmoUltimaHora = -20.1
            s.minutosAteFim = 75
            return s
        case .cheia:
            let leitura = leituraExemplo(percentual: 100, capacidade: 6000, correnteMa: 430, tensaoMv: 11600,
                                         carregando: false, naTomada: true, cheia: true)
            var s = exemploDescarregando
            s.leitura = leitura
            s.estado = .cheia
            s.ritmoMedio = 0; s.ritmoAgora = 0; s.ritmoUltimaHora = nil
            s.minutosAteFim = nil; s.minutosAte80 = nil
            s.detalhes.poucaEnergia = false
            s.apps = []
            return s
        }
    }
}
