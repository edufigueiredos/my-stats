import SwiftUI

// Painel do módulo Calendário: mês com pontos nos dias com compromisso, lista do dia escolhido e "Próximos dias".
// Os compromissos vêm de LeiturasModulos.calendario (EventKit, só na memória). Sem Toggle, Picker nem Menu nativos
// (o ImageRenderer do --foto não os desenha).

struct PainelCalendario: View {
    @Environment(\.estilo) private var estilo
    let leituras: LeiturasModulos
    let acoes: AcoesModulo
    var alturaMaxima: CGFloat? = nil

    /// Primeiro dia do mês mostrado.
    @State private var mes: Date
    @State private var selecionado: Date

    init(leituras: LeiturasModulos, acoes: AcoesModulo, alturaMaxima: CGFloat? = nil) {
        self.leituras = leituras
        self.acoes = acoes
        self.alturaMaxima = alturaMaxima
        let hoje = Calendar.current.startOfDay(for: leituras.data)
        _mes = State(initialValue: Self.primeiroDoMes(hoje))
        _selecionado = State(initialValue: hoje)
    }

    private var cal: Calendar { Calendar.current }
    private var hoje: Date { cal.startOfDay(for: leituras.data) }
    private var agora: Date { leituras.data }
    private var leitura: LeituraCalendario { leituras.calendario ?? LeituraCalendario() }
    private var autorizacao: AutorizacaoCalendario { leitura.autorizacao }

    private static func primeiroDoMes(_ d: Date) -> Date {
        let c = Calendar.current
        return c.date(from: c.dateComponents([.year, .month], from: d)) ?? c.startOfDay(for: d)
    }

    var body: some View {
        MolduraPainelModulo(alturaMaxima: alturaMaxima) {
            CabecalhoModulo(icone: .calendario, titulo: "Calendário", subtitulo: subtitulo, corPonto: estilo.destaqueTopo,
                            rotuloPreferencias: "Preferências do calendário", aoPreferencias: acoes.preferencias)

            cartaoMes

            switch autorizacao {
            case .permitida:
                cartaoDia
                proximosDias
            case .naoPedida:
                cartaoPermissao(titulo: "Mostrar seus compromissos",
                                texto: "O Mac pede a sua permissão para ler o Calendário. Os compromissos ficam só na memória e não saem daqui.",
                                botao: "Permitir acesso ao Calendário", acao: acoes.permitirCalendario)
            case .negada:
                cartaoPermissao(titulo: "Sem acesso ao Calendário",
                                texto: "Libere o Calendário nos Ajustes do Sistema para ver aqui os seus compromissos.",
                                botao: "Abrir Ajustes de Privacidade", acao: abrirAjustesPrivacidade)
            }
        } rodape: {
            RodapeModulo(tituloBotao: Modulo.calendario.tituloAbrirApp, acaoBotao: acoes.abrirApp,
                         textoEsquerda: "Visão geral", acaoEsquerda: acoes.visaoGeral, sair: acoes.sair)
        }
        .onAppear { acoes.mesCalendario(mes) }
    }

    private var subtitulo: String {
        "\(FormatoData.diaExtenso(hoje)) · semana \(FormatoData.semanaDoAno(hoje))"
    }

    private func abrirAjustesPrivacidade() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Mês

    private var mesDeHoje: Bool { cal.isDate(mes, equalTo: hoje, toGranularity: .month) }

    private func mudarMes(_ delta: Int) {
        guard let novo = cal.date(byAdding: .month, value: delta, to: mes) else { return }
        irPara(novo)
    }

    private func irPara(_ data: Date) {
        let primeiro = Self.primeiroDoMes(data)
        mes = primeiro
        // O dia escolhido sempre fica dentro do mês mostrado, para a lista ter o que mostrar.
        selecionado = cal.isDate(primeiro, equalTo: hoje, toGranularity: .month) ? hoje : primeiro
        acoes.mesCalendario(primeiro)
    }

    private var cartaoMes: some View {
        Cartao(padding: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(FormatoData.mesAno(mes)).font(.system(size: 16, weight: .bold))
                    Spacer(minLength: 8)
                    if !mesDeHoje || selecionado != hoje {
                        Button { irPara(hoje) } label: {
                            Text("Hoje").font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 11).frame(height: 26)
                                .background(Capsule().fill(estilo.ladrilho))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Voltar para hoje")
                    }
                    botaoMes("chevron.left", rotulo: "Mês anterior") { mudarMes(-1) }
                    botaoMes("chevron.right", rotulo: "Próximo mês") { mudarMes(1) }
                }
                HStack(spacing: 0) {
                    ForEach(Array(FormatoData.iniciaisSemana.enumerated()), id: \.offset) { _, letra in
                        Text(letra).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.5))
                            .frame(maxWidth: .infinity)
                    }
                }
                VStack(spacing: 2) {
                    ForEach(semanas.indices, id: \.self) { s in
                        HStack(spacing: 0) {
                            ForEach(semanas[s], id: \.self) { dia in celula(dia) }
                        }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
        }
    }

    private func botaoMes(_ icone: String, rotulo: String, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: icone)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.8))
                .frame(width: 28, height: 26)
                .background(Capsule().fill(estilo.ladrilho))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rotulo)
    }

    /// Dias da grade, semana por semana, a partir do primeiro dia da semana do usuário.
    private var semanas: [[Date]] {
        let diasNoMes = cal.range(of: .day, in: .month, for: mes)?.count ?? 30
        let deslocamento = (cal.component(.weekday, from: mes) - cal.firstWeekday + 7) % 7
        let linhas = Int((Double(deslocamento + diasNoMes) / 7).rounded(.up))
        guard let inicio = cal.date(byAdding: .day, value: -deslocamento, to: mes) else { return [] }
        return (0..<linhas).map { l in
            (0..<7).compactMap { c in cal.date(byAdding: .day, value: l * 7 + c, to: inicio) }
        }
    }

    private func temCompromisso(_ dia: Date) -> Bool {
        autorizacao == .permitida && leitura.compromissos.contains { $0.cobre(dia, calendario: cal) }
    }

    private func celula(_ dia: Date) -> some View {
        let ehHoje = cal.isDate(dia, inSameDayAs: hoje)
        let ehSel = cal.isDate(dia, inSameDayAs: selecionado)
        let doMes = cal.isDate(dia, equalTo: mes, toGranularity: .month)
        let numero = cal.component(.day, from: dia)
        return Button {
            selecionado = dia
            if !doMes { irParaMesDe(dia) }
        } label: {
            VStack(spacing: 1) {
                ZStack {
                    if ehHoje {
                        Circle().fill(estilo.degrade)
                    } else if ehSel {
                        Circle().strokeBorder(estilo.destaque, lineWidth: 1.6)
                    }
                    if ehHoje && ehSel {
                        Circle().strokeBorder(estilo.sobreDestaque.opacity(0.55), lineWidth: 1.2).padding(2)
                    }
                    Text("\(numero)")
                        .font(.system(size: 14, weight: ehHoje ? .bold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(ehHoje ? estilo.sobreDestaque : Color.primary.opacity(doMes ? 0.95 : 0.3))
                }
                .frame(width: 30, height: 30)
                Circle()
                    .fill(temCompromisso(dia) ? estilo.destaque.opacity(doMes ? 1 : 0.4) : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(FormatoData.diaExtenso(dia) + (temCompromisso(dia) ? ", com compromissos" : ""))
        .accessibilityAddTraits(ehSel ? .isSelected : [])
    }

    /// Clicar num dia apagado de outro mês leva o painel para aquele mês, mantendo o dia escolhido.
    private func irParaMesDe(_ dia: Date) {
        let primeiro = Self.primeiroDoMes(dia)
        mes = primeiro
        selecionado = dia
        acoes.mesCalendario(primeiro)
    }

    // MARK: Lista do dia

    private func compromissos(em dia: Date) -> [Compromisso] {
        leitura.compromissos
            .filter { $0.cobre(dia, calendario: cal) }
            .sorted { a, b in
                if a.diaInteiro != b.diaInteiro { return a.diaInteiro }
                return a.inicio < b.inicio
            }
    }

    private var cartaoDia: some View {
        let lista = compromissos(em: selecionado)
        return VStack(alignment: .leading, spacing: 8) {
            CabecalhoSecao(FormatoData.tituloDia(selecionado, hoje: hoje))
            Cartao(padding: 0) {
                if lista.isEmpty {
                    Text("Nada marcado")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.primary.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                } else {
                    VStack(spacing: 0) {
                        ForEach(lista) { c in linha(c) }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                }
            }
        }
    }

    private func linha(_ c: Compromisso) -> some View {
        let acabou = c.acabou(em: agora)
        return HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color(hex: c.corHex))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(FormatoData.faixaHorario(c))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary.opacity(0.62))
                Text(c.titulo).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                if let local = c.local {
                    Text(local).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.55)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 6)
        .opacity(acabou ? 0.45 : 1)
    }

    // MARK: Próximos dias

    private var proximosDias: some View {
        // Até 6 compromissos dos 7 dias depois do escolhido, agrupados por dia.
        var grupos: [(dia: Date, itens: [Compromisso])] = []
        var restantes = 6
        for delta in 1...7 {
            guard restantes > 0, let dia = cal.date(byAdding: .day, value: delta, to: selecionado) else { break }
            let doDia = Array(compromissos(em: dia).prefix(restantes))
            if !doDia.isEmpty {
                grupos.append((dia, doDia))
                restantes -= doDia.count
            }
        }
        return Group {
            if !grupos.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    CabecalhoSecao("Próximos dias").padding(.top, 2)
                    Cartao(padding: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(grupos.indices, id: \.self) { g in
                                Text(FormatoData.diaExtenso(grupos[g].dia))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.primary.opacity(0.62))
                                    .padding(.top, g == 0 ? 8 : 10)
                                    .padding(.bottom, 2)
                                ForEach(grupos[g].itens) { c in linha(c) }
                            }
                        }
                        .padding(.horizontal, 14).padding(.bottom, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    // MARK: Sem permissão

    private func cartaoPermissao(titulo: String, texto: String, botao: String, acao: @escaping () -> Void) -> some View {
        Cartao(padding: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(titulo).font(.system(size: 15, weight: .bold))
                Text(texto)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: acao) {
                    Text(botao)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(estilo.primeiroPlanoSelecionado)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(FundoSelecionavel(selecionado: true, raio: 18))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
        }
    }
}
