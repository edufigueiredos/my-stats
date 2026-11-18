import Foundation
import AppKit
import EventKit

/// Lê os compromissos do Calendário (EventKit). Só existe na memória: nada é gravado em disco nem vai para log.
/// A permissão só é pedida por `pedirPermissao()`, que o monitor chama com o módulo ligado e o painel aberto
/// (ou quando a pessoa toca no botão do painel).
@MainActor
final class LeitorCalendario {
    private(set) var leitura = LeituraCalendario()
    /// Avisa o monitor quando a leitura muda fora do ciclo dele (recarga de 60 s, mudança no Calendário, permissão).
    var aoMudar: (() -> Void)?

    private lazy var loja = EKEventStore()
    private var timer: Timer?
    private var observador: NSObjectProtocol?
    private var mes: Date
    private var pedindo = false

    init() { mes = Self.primeiroDoMes(Date()) }

    var autorizacao: AutorizacaoCalendario {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .permitida
        case .notDetermined: return .naoPedida
        default: return .negada
        }
    }

    // MARK: Ciclo

    /// Liga ou desliga a leitura. Desligada, solta timer, observador e compromissos da memória.
    func definirAtivo(_ ativo: Bool) {
        guard ativo else {
            timer?.invalidate()
            timer = nil
            if let o = observador { NotificationCenter.default.removeObserver(o) }
            observador = nil
            if !leitura.compromissos.isEmpty || leitura.autorizacao != .naoPedida { leitura = LeituraCalendario() }
            return
        }
        guard timer == nil else { return }
        recarregar(avisar: false)
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recarregar(avisar: true) }
        }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        timer = t
        observador = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recarregar(avisar: true) }
        }
    }

    /// Mês que o painel mostra: a janela de busca começa no primeiro dia dele.
    func definirMes(_ data: Date) {
        let novo = Self.primeiroDoMes(data)
        guard !Calendar.current.isDate(novo, inSameDayAs: mes) else { return }
        mes = novo
        guard timer != nil else { return }
        recarregar(avisar: true)
    }

    /// Mostra o pedido do sistema (só com a autorização ainda não decidida).
    func pedirPermissao() {
        guard autorizacao == .naoPedida, !pedindo else { return }
        pedindo = true
        let loja = self.loja
        Task { @MainActor [weak self] in
            _ = try? await loja.requestFullAccessToEvents()
            self?.pedindo = false
            self?.recarregar(avisar: true)
        }
    }

    // MARK: Leitura

    private func recarregar(avisar: Bool) {
        let nova = ler()
        if nova != leitura {
            leitura = nova
            if avisar { aoMudar?() }
        }
    }

    private func ler() -> LeituraCalendario {
        let aut = autorizacao
        guard aut == .permitida else { return LeituraCalendario(autorizacao: aut) }
        let cal = Calendar.current
        let hoje = cal.startOfDay(for: Date())
        let inicio = min(Self.primeiroDoMes(mes), hoje)
        let fimMes = cal.date(byAdding: .month, value: 1, to: Self.primeiroDoMes(mes)) ?? hoje
        let fim = max(cal.date(byAdding: .day, value: 8, to: fimMes) ?? fimMes, cal.date(byAdding: .day, value: 8, to: hoje) ?? hoje)
        let filtro = loja.predicateForEvents(withStart: inicio, end: fim, calendars: nil)
        let eventos = loja.events(matching: filtro).sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        let lista: [Compromisso] = eventos.prefix(400).compactMap { e in
            guard let ini = e.startDate, let fimEv = e.endDate else { return nil }
            let titulo = (e.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let local = e.location?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Compromisso(
                id: (e.eventIdentifier ?? UUID().uuidString) + "@\(Int(ini.timeIntervalSince1970))",
                titulo: titulo.isEmpty ? "Sem título" : titulo, inicio: ini, fim: fimEv, diaInteiro: e.isAllDay,
                corHex: Self.hex(e.calendar?.color), local: (local?.isEmpty ?? true) ? nil : local)
        }
        return LeituraCalendario(autorizacao: .permitida, compromissos: lista)
    }

    private static func primeiroDoMes(_ d: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? cal.startOfDay(for: d)
    }

    private static func hex(_ cor: NSColor?) -> String {
        guard let c = cor?.usingColorSpace(.sRGB) else { return "#4C8DF6" }
        func b(_ v: CGFloat) -> Int { min(max(Int((v * 255).rounded()), 0), 255) }
        return String(format: "#%02X%02X%02X", b(c.redComponent), b(c.greenComponent), b(c.blueComponent))
    }
}

// MARK: - Datas e textos

extension Compromisso {
    /// O compromisso toca o dia (dias inteiros e os que passam da meia-noite aparecem em cada dia que cobrem).
    func cobre(_ dia: Date, calendario cal: Calendar = .current) -> Bool {
        let ini = cal.startOfDay(for: dia)
        guard let fimDia = cal.date(byAdding: .day, value: 1, to: ini) else { return false }
        return inicio < fimDia && (fim > ini || inicio >= ini)
    }

    func acabou(em agora: Date) -> Bool { fim <= agora }
}

/// Textos de data em pt-BR, com o primeiro dia da semana do usuário. Sem DateFormatter: tudo vem dos nomes do calendário.
enum FormatoData {
    private static var cal: Calendar {
        var c = Calendar.current
        let primeiro = c.firstWeekday
        c.locale = Locale(identifier: "pt_BR")
        c.firstWeekday = primeiro
        return c
    }

    private static func semPonto(_ t: String) -> String { t.replacingOccurrences(of: ".", with: "").lowercased() }

    private static func diaSemanaCurto(_ d: Date, _ c: Calendar) -> String {
        semPonto(c.shortWeekdaySymbols[c.component(.weekday, from: d) - 1])
    }

    /// "sexta", "sábado", "domingo".
    static func diaSemana(_ d: Date) -> String {
        let c = cal
        let nome = c.weekdaySymbols[c.component(.weekday, from: d) - 1].lowercased()
        return nome.components(separatedBy: "-").first ?? nome
    }

    /// Partes da data para o Texto livre do Calendário: marcador → valor ("seg", "16", "nov", "2026"...).
    static func partes(_ d: Date) -> [(marcador: String, valor: String)] {
        let c = cal
        let dia = c.component(.day, from: d), mes = c.component(.month, from: d), ano = c.component(.year, from: d)
        return [
            ("{semana}", diaSemanaCurto(d, c)),
            ("{semanalonga}", diaSemana(d)),
            ("{dia}", "\(dia)"),
            ("{dia2}", String(format: "%02d", dia)),
            ("{mes}", semPonto(c.shortMonthSymbols[mes - 1])),
            ("{meslongo}", c.monthSymbols[mes - 1].lowercased()),
            ("{mesnum}", String(format: "%02d", mes)),
            ("{ano}", "\(ano)"),
            ("{ano2}", String(format: "%02d", ano % 100)),
        ]
    }

    /// Títulos dos botões das partes da data, na ordem de `partes`.
    static let titulosPartes = ["Dia da semana", "Semana por extenso", "Dia", "Dia com 0", "Mês", "Mês por extenso",
                                "Mês em número", "Ano", "Ano com 2 dígitos"]

    /// "sex 14 nov", para a barra.
    static func dataBarra(_ d: Date) -> String {
        let c = cal
        return "\(diaSemanaCurto(d, c)) \(c.component(.day, from: d)) \(semPonto(c.shortMonthSymbols[c.component(.month, from: d) - 1]))"
    }

    /// "sexta, 14 de novembro".
    static func diaExtenso(_ d: Date) -> String {
        let c = cal
        return "\(diaSemana(d)), \(c.component(.day, from: d)) de \(c.monthSymbols[c.component(.month, from: d) - 1].lowercased())"
    }

    /// "Novembro 2026".
    static func mesAno(_ d: Date) -> String {
        let c = cal
        let mes = c.monthSymbols[c.component(.month, from: d) - 1]
        return "\(mes.prefix(1).uppercased() + mes.dropFirst()) \(c.component(.year, from: d))"
    }

    static func semanaDoAno(_ d: Date) -> Int { Calendar.current.component(.weekOfYear, from: d) }

    /// Iniciais dos dias da semana, a partir do primeiro dia do calendário do usuário ("D S T Q Q S S").
    static var iniciaisSemana: [String] {
        let c = cal
        let s = c.veryShortStandaloneWeekdaySymbols
        let primeiro = c.firstWeekday - 1
        return (0..<7).map { s[(primeiro + $0) % 7].uppercased() }
    }

    /// "09:00–10:00" ou "Dia inteiro".
    static func faixaHorario(_ c: Compromisso) -> String {
        c.diaInteiro ? "Dia inteiro" : "\(Formato.horario(c.inicio))–\(Formato.horario(c.fim))"
    }

    /// "Hoje" ou "sábado, 15 de novembro".
    static func tituloDia(_ d: Date, hoje: Date) -> String {
        Calendar.current.isDate(d, inSameDayAs: hoje) ? "Hoje" : diaExtenso(d)
    }

    /// Para a barra: o próximo compromisso de hoje que ainda não acabou, "15:30 Reunião de equipe", até ~22 caracteres.
    static func proximoCompromisso(_ l: LeiturasModulos) -> String {
        guard let cal = l.calendario, cal.autorizacao == .permitida else { return Formato.semDado }
        let c = Calendar.current
        let proximo = cal.compromissos
            .filter { $0.cobre(l.data) && !$0.acabou(em: l.data) }
            .min { a, b in
                // Dia inteiro vai depois dos com horário; entre os demais, o que começa antes.
                if a.diaInteiro != b.diaInteiro { return !a.diaInteiro }
                return a.inicio < b.inicio
            }
        guard let p = proximo else { return "Sem compromissos" }
        let texto = p.diaInteiro || !c.isDate(p.inicio, inSameDayAs: l.data) ? p.titulo : "\(Formato.horario(p.inicio)) \(p.titulo)"
        return texto.count > 22 ? String(texto.prefix(21)).trimmingCharacters(in: .whitespaces) + "…" : texto
    }
}
