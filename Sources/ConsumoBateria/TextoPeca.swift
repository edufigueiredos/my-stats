import Foundation

/// Texto das peças do item da barra: funções puras que montam cada trecho a partir da situação
/// e das opções da peça (`ItemPeca`). Com `item` nil, ou com os campos novos nil, o resultado é
/// o mesmo das predefinições antigas.
enum TextoPeca {
    /// Texto inicial de uma peça de texto livre recém-colocada.
    static let textoLivrePadrao = "{pct} · {tempo}"
    /// Texto da peça Etiqueta quando o usuário não escreveu outro.
    static let etiquetaPadrao = "BAT"

    /// Marcadores aceitos no texto livre, na ordem em que aparecem no editor.
    static let marcadores: [(marcador: String, titulo: String)] = [
        ("{ritmo}", "Ritmo"),
        ("{pct}", "Carga"),
        ("{tempo}", "Tempo"),
        ("{watts}", "Watts"),
        ("{horario}", "Horário"),
    ]

    private static func semUnidade(_ item: ItemPeca?) -> Bool { item?.unidade == false }

    /// Ritmo médio (ou o de agora, sem média): "−11,3 %/h". Com `espaco` falso: "−11,3%/h".
    /// Com a unidade desligada na peça: "−11,3". Casas e sentido da peça valem sobre os globais.
    static func ritmo(_ s: Situacao, item: ItemPeca?, casas: Int, sentido: SentidoRitmo, espaco: Bool) -> String {
        let v = s.ritmoMedio ?? s.ritmoAgora
        let numero = Formato.ritmo(v, casas: item?.casas ?? casas, sentido: item?.sentido ?? sentido, unidade: false)
        if semUnidade(item) { return numero }
        return numero + (espaco ? " %/h" : "%/h")
    }

    /// Carga: "54%"; com a unidade desligada, "54".
    static func porcentagem(_ s: Situacao, item: ItemPeca?) -> String {
        semUnidade(item) ? "\(s.leitura.percentual)" : Formato.percentual(s.leitura.percentual)
    }

    /// Potência em módulo: "10,7 W". Carregando mostra o que entra no sistema (0 casas); parado e
    /// cheia, 0 casas; descarregando, 1 casa. `casas` da peça troca as casas; sem unidade, "10,7".
    static func watts(_ s: Situacao, item: ItemPeca?) -> String {
        let valor: Double?
        let casasPadrao: Int
        switch s.estado {
        case .carregando:
            valor = s.detalhes.entradaSistemaW ?? s.leitura.watts
            casasPadrao = 0
        case .parado, .cheia:
            valor = s.leitura.watts
            casasPadrao = 0
        default:
            valor = s.leitura.watts
            casasPadrao = 1
        }
        let texto = Formato.watts(valor, casas: item?.casas ?? casasPadrao)
        return semUnidade(item) ? String(texto.dropLast(2)) : texto
    }

    /// Tempo restante. Parado e cheia: "Parado"/"Cheia" ("tomada" no modo `curto`). Nos demais,
    /// segue o formato da peça: "4:46" (padrão), "4h46" ("46min" abaixo de uma hora),
    /// horário em que acaba ("18:25") ou "286 min". Sem dado: "–".
    static func tempo(_ s: Situacao, item: ItemPeca?, curto: Bool) -> String {
        switch s.estado {
        case .parado: return curto ? "tomada" : "Parado"
        case .cheia: return curto ? "tomada" : "Cheia"
        default: break
        }
        switch item?.formatoTempo ?? .relogio {
        case .relogio:
            return Formato.duracao(minutos: s.minutosAteFim)
        case .horasMinutos:
            guard let m = s.minutosAteFim, m.isFinite, m >= 0 else { return "–" }
            let total = Int(m.rounded())
            return total < 60 ? "\(total)min" : String(format: "%dh%02d", total / 60, total % 60)
        case .horarioFim:
            return s.horarioFim.map { Formato.horario($0) } ?? "–"
        case .minutos:
            guard let m = s.minutosAteFim, m.isFinite, m >= 0 else { return "–" }
            return "\(Int(m.rounded())) min"
        }
    }

    /// Horário em que a bateria acaba (ou termina de carregar): "18:25". Parado e cheia: "–".
    static func horario(_ s: Situacao, item: ItemPeca?) -> String {
        s.horarioFim.map { Formato.horario($0) } ?? "–"
    }

    /// Troca {ritmo}, {pct}, {tempo}, {watts} e {horario} pelos valores atuais, por exemplo
    /// "{pct} · {tempo}" vira "54% · 4:46". Marcadores desconhecidos ficam como estão e o
    /// resultado é cortado em `ItemPeca.limiteTexto` caracteres.
    static func expandir(_ modelo: String, _ s: Situacao, item: ItemPeca?, casas: Int, sentido: SentidoRitmo) -> String {
        var texto = modelo
        let valores: [(String, () -> String)] = [
            ("{ritmo}", { ritmo(s, item: item, casas: casas, sentido: sentido, espaco: true) }),
            ("{pct}", { porcentagem(s, item: item) }),
            ("{tempo}", { tempo(s, item: item, curto: false) }),
            ("{watts}", { watts(s, item: item) }),
            ("{horario}", { horario(s, item: item) }),
        ]
        for (marcador, valor) in valores where texto.contains(marcador) {
            texto = texto.replacingOccurrences(of: marcador, with: valor())
        }
        return String(texto.prefix(ItemPeca.limiteTexto))
    }

    /// Prefixo e sufixo da peça em volta do texto: prefixo "~" + "4:46" + sufixo " h" = "~4:46 h".
    static func moldura(_ texto: String, item: ItemPeca?) -> String {
        (item?.prefixo ?? "") + texto + (item?.sufixo ?? "")
    }

    /// Texto da peça Etiqueta: o que o usuário escreveu, ou "BAT".
    static func etiqueta(item: ItemPeca?) -> String {
        if let t = item?.texto, !t.isEmpty { return t }
        return etiquetaPadrao
    }
}
