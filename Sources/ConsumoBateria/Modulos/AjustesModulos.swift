import Foundation
import Observation

/// O que vai para o UserDefaults (chave "modulosSistema"), num JSON só.
struct GravadoModulos: Codable, Sendable, Equatable {
    var modulos: [AjusteModulo]
    var modoBarra: ModoBarraModulos
    var intervalo: IntervaloModulos
    var bateriaNaBarra: Bool

    init(modulos: [AjusteModulo], modoBarra: ModoBarraModulos = .umPorModulo, intervalo: IntervaloModulos = .dois,
         bateriaNaBarra: Bool = true) {
        self.modulos = modulos
        self.modoBarra = modoBarra
        self.intervalo = intervalo
        self.bateriaNaBarra = bateriaNaBarra
    }

    private enum CodingKeys: String, CodingKey { case modulos, modoBarra, intervalo, bateriaNaBarra }

    private struct Cru: Decodable {
        let valor: AjusteModulo?
        init(from decoder: Decoder) throws { valor = try? AjusteModulo(from: decoder) }
    }

    /// Ignora módulo desconhecido ou repetido e acrescenta, no lugar padrão, o que a config não tinha.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let crus = (try? c.decodeIfPresent([Cru].self, forKey: .modulos)) ?? []
        var lista: [AjusteModulo] = []
        for a in crus.compactMap(\.valor) where !lista.contains(where: { $0.modulo == a.modulo }) {
            lista.append(a)
        }
        let ordem = AjustesModulos.ordemPadrao
        for (i, m) in ordem.enumerated() where !lista.contains(where: { $0.modulo == m }) {
            let novo = AjusteModulo.padrao(m)
            if let seguinte = ordem[(i + 1)...].first(where: { t in lista.contains(where: { $0.modulo == t }) }),
               let j = lista.firstIndex(where: { $0.modulo == seguinte }) {
                lista.insert(novo, at: j)
            } else {
                lista.append(novo)
            }
        }
        modulos = lista
        modoBarra = (try? c.decodeIfPresent(ModoBarraModulos.self, forKey: .modoBarra)) ?? .umPorModulo
        intervalo = (try? c.decodeIfPresent(IntervaloModulos.self, forKey: .intervalo)) ?? .dois
        bateriaNaBarra = try c.decodeIfPresent(Bool.self, forKey: .bateriaNaBarra) ?? true
    }
}

/// Ajustes dos módulos do sistema, gravados no UserDefaults a cada mudança. Com `persistir: false` (--foto) é volátil.
@MainActor
@Observable
final class AjustesModulos {
    static let compartilhado = AjustesModulos()

    nonisolated static let chave = "modulosSistema"
    /// Ordem da barra, da esquerda para a direita (a do desenho Main.dc.html).
    nonisolated static let ordemPadrao: [Modulo] = [.cpu, .gpu, .disco, .memoria, .rede, .sensores, .calendario]

    @ObservationIgnored private let persistir: Bool
    @ObservationIgnored private let defaults = UserDefaults.standard

    var modulos: [AjusteModulo] = AjustesModulos.ordemPadrao.map { AjusteModulo.padrao($0) } { didSet { gravar() } }
    var modoBarra: ModoBarraModulos = .umPorModulo { didSet { gravar() } }
    var intervalo: IntervaloModulos = .dois { didSet { gravar() } }
    var bateriaNaBarra = true { didSet { gravar() } }

    init(persistir: Bool = true) {
        self.persistir = persistir
        guard persistir, let dados = defaults.data(forKey: Self.chave) else { return }
        let g = Self.decodificar(dados)
        modulos = g.modulos
        modoBarra = g.modoBarra
        intervalo = g.intervalo
        bateriaNaBarra = g.bateriaNaBarra
    }

    nonisolated static func decodificar(_ dados: Data?) -> GravadoModulos {
        if let dados, let g = try? JSONDecoder().decode(GravadoModulos.self, from: dados) { return g }
        return (try? JSONDecoder().decode(GravadoModulos.self, from: Data("{}".utf8)))
            ?? GravadoModulos(modulos: ordemPadrao.map { AjusteModulo.padrao($0) })
    }

    private func gravar() {
        guard persistir else { return }
        let g = GravadoModulos(modulos: modulos, modoBarra: modoBarra, intervalo: intervalo, bateriaNaBarra: bateriaNaBarra)
        guard let dados = try? JSONEncoder().encode(g) else { return }
        defaults.set(dados, forKey: Self.chave)
    }

    // MARK: Consulta

    func ajuste(_ m: Modulo) -> AjusteModulo {
        modulos.first(where: { $0.modulo == m }) ?? AjusteModulo.padrao(m)
    }

    private func indice(_ m: Modulo) -> Int? { modulos.firstIndex(where: { $0.modulo == m }) }

    var ligados: [Modulo] { modulos.filter(\.ligado).map(\.modulo) }

    /// Itens da barra, da esquerda para a direita; cada item é o conjunto de módulos que ele mostra.
    var itensNaBarra: [[Modulo]] {
        let lig = modulos.filter(\.ligado)
        switch modoBarra {
        case .umPorModulo: return lig.map { [$0.modulo] }
        case .umItemSo: return lig.isEmpty ? [] : [lig.map(\.modulo)]
        case .grupos:
            var feitos = Set<Int>()
            var saida: [[Modulo]] = []
            for a in lig {
                guard let g = a.grupo else { saida.append([a.modulo]); continue }
                if feitos.insert(g).inserted {
                    saida.append(lig.filter { $0.grupo == g }.map(\.modulo))
                }
            }
            return saida
        }
    }

    /// Sensores ligado, ou alguma peça de módulo ligado que lê temperatura, potência ou ventoinha.
    var precisaSensores: Bool {
        let usam: Set<PecaModulo> = [.temperatura, .tempGPU, .potencia, .ventoinha, .ventoinhaPct]
        return modulos.contains { a in
            a.ligado && (a.modulo == .sensores || (a.config.pecas + a.config.pecasBaixo).contains { usam.contains($0.peca) })
        }
    }

    // MARK: Mudanças

    func alternar(_ m: Modulo, ligado: Bool) {
        guard let i = indice(m), modulos[i].ligado != ligado else { return }
        modulos[i].ligado = ligado
        if !ligado && ligados.isEmpty { bateriaNaBarra = true }
    }

    /// Esconder a bateria só vale com algum módulo ligado. Devolve se o pedido foi aceito.
    @discardableResult
    func alternarBateria(_ ligada: Bool) -> Bool {
        if !ligada && ligados.isEmpty { return false }
        bateriaNaBarra = ligada
        return true
    }

    func mover(_ m: Modulo, para destino: Int) {
        guard let i = indice(m) else { return }
        let item = modulos.remove(at: i)
        modulos.insert(item, at: min(max(destino, 0), modulos.count))
    }

    func mover(_ m: Modulo, _ delta: Int) {
        guard let i = indice(m) else { return }
        mover(m, para: i + delta)
    }

    /// Dá o mesmo número de grupo aos dois e passa a barra para Grupos; `nil` tira o módulo do grupo.
    func juntar(_ m: Modulo, com outro: Modulo?) {
        guard let i = indice(m) else { return }
        guard let outro, outro != m, let j = indice(outro) else {
            modulos[i].grupo = nil
            return
        }
        let g = modulos[j].grupo ?? ((modulos.compactMap(\.grupo).max() ?? 0) + 1)
        modulos[j].grupo = g
        modulos[i].grupo = g
        modoBarra = .grupos
    }

    /// Troca o formato pronto, mantendo a faixa e a cor por faixa.
    func aplicarFormato(_ f: FormatoModulo, em m: Modulo) {
        guard let i = indice(m) else { return }
        var nova = f.config(para: m)
        nova.faixa = modulos[i].config.faixa
        nova.corPorFaixa = modulos[i].config.corPorFaixa
        modulos[i].formato = f
        modulos[i].config = nova
    }

    func atualizarConfig(_ m: Modulo, _ mudar: (inout ConfigModulo) -> Void) {
        guard let i = indice(m) else { return }
        var c = modulos[i].config
        mudar(&c)
        modulos[i].config = c.saneado()
    }

    func atualizarAviso(_ m: Modulo, _ aviso: AvisoModulo) {
        guard let i = indice(m), let j = modulos[i].avisos.firstIndex(where: { $0.tipo == aviso.tipo }) else { return }
        modulos[i].avisos[j] = aviso
    }

    func definirAoClicar(_ m: Modulo, _ a: AoClicarModulo) {
        guard let i = indice(m) else { return }
        modulos[i].aoClicar = a
    }

    // MARK: Compatibilidade (--foto)

    /// Decodifica três JSONs (vazio, parcial, completo com peça desconhecida) e confere o resultado.
    nonisolated static func checarCompatibilidade() -> Bool {
        let vazio = Data("{}".utf8)
        let parcial = Data(#"{"modulos":[{"modulo":"cpu","ligado":true}]}"#.utf8)

        let padrao = GravadoModulos(modulos: ordemPadrao.map { m in
            var a = AjusteModulo.padrao(m)
            a.ligado = m == .cpu
            return a
        })
        guard let codificado = try? JSONEncoder().encode(padrao),
              var raiz = (try? JSONSerialization.jsonObject(with: codificado)) as? [String: Any],
              var lista = raiz["modulos"] as? [[String: Any]], !lista.isEmpty,
              var config = lista[0]["config"] as? [String: Any],
              var pecas = config["pecas"] as? [[String: Any]]
        else { return false }
        let antes = pecas.count
        pecas.append(["id": UUID().uuidString, "peca": "xyz"])
        config["pecas"] = pecas
        lista[0]["config"] = config
        raiz["modulos"] = lista
        guard let completo = try? JSONSerialization.data(withJSONObject: raiz) else { return false }

        // Config gravada antes do Calendário existir: os seis módulos antigos; o novo entra por último e desligado.
        var antigaRaiz = raiz
        antigaRaiz["modulos"] = lista.filter { ($0["modulo"] as? String) != Modulo.calendario.rawValue }
        guard let antigaDados = try? JSONSerialization.data(withJSONObject: antigaRaiz) else { return false }
        let d = decodificar(antigaDados)
        guard d.modulos.count == ordemPadrao.count, d.modulos.last?.modulo == .calendario, d.modulos.last?.ligado == false,
              d.modulos.first(where: { $0.modulo == .cpu })?.ligado == true else { return false }

        let a = decodificar(vazio)
        let b = decodificar(parcial)
        let c = decodificar(completo)
        guard a.modulos.count == ordemPadrao.count, !a.modulos.contains(where: \.ligado) else { return false }
        guard b.modulos.count == ordemPadrao.count, b.modulos.first(where: { $0.modulo == .cpu })?.ligado == true else { return false }
        guard c.modulos.count == ordemPadrao.count, c.modulos.first(where: { $0.modulo == .cpu })?.ligado == true,
              c.modulos.first(where: { $0.modulo == .cpu })?.config.pecas.count == antes else { return false }
        return true
    }
}
