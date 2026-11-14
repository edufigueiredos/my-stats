import SwiftUI

// Painel do módulo Rede (docs/desenho/modulos/PainelRede.dc.html). Dados de LeiturasModulos/SeriesModulos.

struct PainelRede: View {
    @Environment(\.estilo) private var estilo
    let leituras: LeiturasModulos
    let series: SeriesModulos
    let acoes: AcoesModulo
    var alturaMaxima: CGFloat? = nil
    var ipPublicoInicial: String? = nil

    @State private var ip: String?
    @State private var carregando = false

    init(leituras: LeiturasModulos, series: SeriesModulos, acoes: AcoesModulo, alturaMaxima: CGFloat? = nil, ipPublicoInicial: String? = nil) {
        self.leituras = leituras
        self.series = series
        self.acoes = acoes
        self.alturaMaxima = alturaMaxima
        self.ipPublicoInicial = ipPublicoInicial
        _ip = State(initialValue: ipPublicoInicial)
    }

    private var rede: LeituraRede? { leituras.rede }
    private var conectado: Bool { rede?.conectado ?? false }
    private var ehWiFi: Bool { rede?.tipo == "Wi-Fi" }

    var body: some View {
        MolduraPainelModulo(alturaMaxima: alturaMaxima) {
            CabecalhoModulo(icone: .rede, titulo: "Rede", subtitulo: subtitulo, corPonto: corPonto,
                            rotuloPreferencias: "Preferências da rede", aoPreferencias: acoes.preferencias)

            cartaoLatencia

            HStack(spacing: 8) {
                tile(rotulo: "Baixando", cor: estilo.destaque, valor: rede.map { Formato.velocidade($0.baixandoBps) } ?? Formato.semDado,
                     hoje: rede?.hojeBaixadoBytes)
                tile(rotulo: "Enviando", cor: Color.primary.opacity(0.5), valor: rede.map { Formato.velocidade($0.enviandoBps) } ?? Formato.semDado,
                     hoje: rede?.hojeEnviadoBytes)
            }

            graficoVelocidade

            if let rede, rede.conectado {
                CabecalhoSecao("Conexão").padding(.top, 2)
                cartaoConexao(rede)
            }

            if let procs = leituras.processos.rede, !procs.isEmpty {
                CabecalhoSecao("Quem mais usa", dica: "↓ · ↑").padding(.top, 2)
                Cartao(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(procs.enumerated()), id: \.element.id) { i, p in
                            LinhaProcesso(indice: i, nome: p.nome,
                                          valor: "\(Formato.velocidade(p.valor)) · \(Formato.velocidade(p.valor2 ?? 0))",
                                          fracao: p.fracao)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
            }
        } rodape: {
            RodapeModulo(tituloBotao: Modulo.rede.tituloAbrirApp, acaoBotao: acoes.abrirApp,
                         textoEsquerda: "Visão geral", acaoEsquerda: acoes.visaoGeral, sair: acoes.sair)
        }
    }

    // MARK: Cabeçalho

    private var subtitulo: String {
        guard let rede, rede.conectado else { return "Sem conexão" }
        if ehWiFi {
            var t = "Wi-Fi"
            if let nome = rede.nomeRede, !nome.isEmpty { t += " " + nome }
            if let banda = rede.banda { t += " · " + banda }
            return t
        }
        return rede.tipo ?? "Conectado"
    }

    private var corPonto: Color {
        guard conectado else { return .quenteModulo }
        if let l = rede?.latenciaMs, l >= 60 { return estilo.destaqueTopo }
        return Paleta.bom
    }

    // MARK: Latência

    private var cartaoLatencia: some View {
        let agora = leituras.data
        let valores = series.valores(.redeLatencia, janela: 120, colunas: 40, agora: agora)
        let pico = series.pico(.redeLatencia, desde: agora.addingTimeInterval(-120))
        // Altura do desenho: v·0,9 + 4, no máximo 56.
        let alturas: [Double?] = valores.map { $0.map { min(56, $0 * 0.9 + 4) } }
        var eixo = ["há 2 min"]
        if let pico, pico.valor >= 60 {
            eixo.append("um pico de \(Int(pico.valor.rounded())) ms às \(Formato.horario(pico.data))")
        }
        eixo.append("agora")
        return Cartao(padding: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        RotuloSecao("Latência · até \(rede?.alvoLatencia ?? "1.1.1.1")")
                        numeroLatencia
                    }
                    Spacer(minLength: 8)
                    if conectado {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("variação \(rede?.variacaoMs.map { Formato.ms($0) } ?? Formato.semDado)")
                            Text("perda \(rede?.perdaPercentual.map { Formato.percentual($0) } ?? Formato.semDado)")
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.7))
                        .monospacedDigit()
                        .padding(.bottom, 6)
                    }
                }
                GraficoColunas(valores: alturas, maximo: 56, altura: 56, cor: { i, _ in
                    (valores[i] ?? 0) >= 60 ? estilo.destaqueTopo : Paleta.bom
                }, opacidade: { _ in 0.9 })
                EixoTempo(eixo)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var numeroLatencia: some View {
        if !conectado {
            Text("sem rede").font(.system(size: 28, weight: .bold)).foregroundStyle(estilo.destaqueTopo)
        } else if let l = rede?.latenciaMs {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Formato.inteiro(Int(l.rounded()))).font(.system(size: 46, weight: .bold)).tracking(-1.4)
                    .foregroundStyle(estilo.destaqueTopo)
                Text("ms").font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.75))
            }
            .monospacedDigit()
        } else {
            Text(Formato.semDado).font(.system(size: 46, weight: .bold)).foregroundStyle(estilo.destaqueTopo)
        }
    }

    // MARK: Velocidade

    private func tile(rotulo: String, cor: Color, valor: String, hoje: UInt64?) -> some View {
        Cartao(padding: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(cor).frame(width: 8, height: 8)
                    Text(rotulo).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.62))
                }
                Text(valor).font(.system(size: 22, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                Text("hoje " + (hoje.map { Formato.bytesDisco($0) } ?? Formato.semDado))
                    .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.62)).monospacedDigit()
            }
        }
    }

    private var graficoVelocidade: some View {
        let agora = leituras.data
        let baixa = series.valores(.redeBaixa, periodo: .dezMin, colunas: 30, agora: agora)
        let sobe = series.valores(.redeSobe, periodo: .dezMin, colunas: 30, agora: agora)
        // Escalas do desenho: 28,2 MB/s enche os 50 pt de cima; 2,67 MB/s enche os 26 pt de baixo.
        let maxCima = max(28.18e6, baixa.compactMap { $0 }.max() ?? 0)
        let maxBaixo = max(2.665e6, sobe.compactMap { $0 }.max() ?? 0)
        return Cartao(padding: 12) {
            GraficoEspelhado(cima: baixa, baixo: sobe, maximoCima: maxCima, maximoBaixo: maxBaixo, alturaCima: 50, alturaBaixo: 26)
        }
    }

    // MARK: Conexão

    private func cartaoConexao(_ r: LeituraRede) -> some View {
        var linhas: [(String, String)] = []
        if ehWiFi {
            let sinal = r.sinalDbm.map { "\(Formato.comSinal(Double($0), casas: 0)) dBm · \(qualidade($0))" } ?? Formato.semDado
            linhas.append(("Sinal", sinal))
            let canal = [r.canal, r.padraoWiFi].compactMap { $0 }.joined(separator: " · ")
            linhas.append(("Canal", canal.isEmpty ? Formato.semDado : canal))
            linhas.append(("Velocidade do link", r.velocidadeLinkMbps.map { Formato.inteiro(Int($0.rounded())) + " Mbit/s" } ?? Formato.semDado))
        }
        linhas.append(("IP local", r.ipLocal ?? Formato.semDado))
        var roteador = r.roteador ?? Formato.semDado
        if r.roteador != nil, let ms = r.latenciaRoteadorMs { roteador += " · " + Formato.ms(ms) }
        linhas.append(("Roteador", roteador))
        linhas.append(("DNS", r.dns.isEmpty ? Formato.semDado : r.dns.joined(separator: ", ")))

        return Cartao(padding: 0) {
            VStack(spacing: 0) {
                ForEach(linhas.indices, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(linhas[i].0).font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.68)).fixedSize()
                        Spacer(minLength: 8)
                        Text(linhas[i].1).font(.system(size: 14)).monospacedDigit().multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 7)
                }
                HStack(spacing: 12) {
                    Text("IP público").font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.68)).fixedSize()
                    Spacer(minLength: 8)
                    if let ip {
                        Text(ip).font(.system(size: 14)).monospacedDigit()
                    } else {
                        Button {
                            guard !carregando else { return }
                            carregando = true
                            Task {
                                let achado = await acoes.buscarIPPublico()
                                ip = achado ?? "não consegui"
                                carregando = false
                            }
                        } label: {
                            Text(carregando ? "Buscando…" : "Mostrar")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(estilo.destaqueTopo)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(estilo.ladrilho))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 7)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
    }

    private func qualidade(_ dbm: Int) -> String {
        if dbm >= -55 { return "ótimo" }
        if dbm >= -67 { return "bom" }
        if dbm >= -75 { return "razoável" }
        return "fraco"
    }
}
