import SwiftUI

// Visão geral dos módulos (docs/desenho/modulos/PainelGeral.dc.html): grade 2×3, cartão da bateria,
// "Quem mais pesa agora" e o rodapé.

struct PainelGeral: View {
    let leituras: LeiturasModulos
    let series: SeriesModulos
    let situacao: Situacao?
    let acoes: AcoesModulo
    var alturaMaxima: CGFloat? = nil
    @Environment(\.estilo) private var estilo

    private var agora: Date { leituras.data }
    private static let gib = 1024.0 * 1024 * 1024
    private static let coresLetra = ["#9CC3F5", "#E8A07C", "#A9A6F2", "#D9D4CA"]

    var body: some View {
        MolduraPainelModulo(alturaMaxima: alturaMaxima) {
            CabecalhoModulo(icone: nil, titulo: "Visão geral", subtitulo: subtitulo, corPonto: corPonto,
                            rotuloPreferencias: "Preferências", aoPreferencias: acoes.preferencias)
            grade
            if let situacao { cartaoBateria(situacao) }
            pesados
        } rodape: {
            RodapeModulo(tituloBotao: "Abrir Monitor de Atividade", acaoBotao: acoes.abrirApp,
                         textoEsquerda: "Preferências…", acaoEsquerda: acoes.preferencias, sair: acoes.sair)
        }
    }

    // MARK: Cabeçalho

    /// A situação mais chamativa, em ordem de gravidade; nil = tudo tranquilo.
    private var destaque: String? {
        if let uso = leituras.cpu?.uso, uso > 70 { return "CPU puxada" }
        if let p = leituras.memoria?.pressao, p != .normal { return "Memória sob pressão" }
        if let c = leituras.sensores?.cpuC, c > 85 { return "CPU quente" }
        if let r = leituras.rede, !r.conectado { return "Sem rede" }
        return nil
    }

    private var subtitulo: String {
        var t = destaque ?? "Tudo tranquilo"
        if let desde = leituras.ligadoDesde {
            let seg = max(agora.timeIntervalSince(desde), 0)
            let dias = Int(seg / 86_400)
            t += " · ligado há " + (dias >= 1 ? "\(dias) \(dias == 1 ? "dia" : "dias")" : Formato.duracaoLonga(seg))
        }
        return t
    }

    private var corPonto: Color { destaque != nil ? estilo.destaqueTopo : Paleta.bom }

    // MARK: Grade

    private struct Bloco {
        var modulo: Modulo
        var valor: String
        var quente: Bool
        var sub: String
        var barras: [Double?]
    }

    private func normalizar(_ v: [Double?]) -> [Double?] {
        let m = max(v.compactMap { $0 }.max() ?? 0, 1e-9)
        return v.map { $0.map { $0 / m * 100 } }
    }

    private var blocos: [Bloco] {
        let s = Formato.semDado
        let dez = PeriodoModulo.dezMin
        let cpu = leituras.cpu, gpu = leituras.gpu, mem = leituras.memoria, disco = leituras.disco, rede = leituras.rede
        let sens = leituras.sensores

        let gpuSub = [leituras.energia?.gpuW.map { Formato.numero($0, casas: 0) + " W" }, sens?.gpuC.map { Formato.temperatura($0, curta: false) }]
            .compactMap { $0 }.joined(separator: " · ")

        var memSub = s
        if let mem {
            memSub = "\(Formato.numero(Double(mem.usadaBytes) / Self.gib, casas: 0)) de \(Formato.numero(Double(mem.totalBytes) / Self.gib, casas: 0)) GB · pressão \(mem.pressao.titulo.lowercased())"
        }
        let interno = disco?.volumes.first(where: \.interno) ?? disco?.volumes.first
        let latencia = rede?.latenciaMs.map { Formato.ms($0) } ?? s
        let sistemaW = sens?.sistemaW.map { Formato.numero($0, casas: 0) }

        return [
            Bloco(modulo: .cpu, valor: cpu.map { Formato.percentual($0.uso) } ?? s, quente: (cpu?.uso ?? 0) >= 60,
                  sub: cpu.map { "usuário \(Int($0.usuario.rounded())) · sistema \(Int($0.sistema.rounded()))" } ?? s,
                  barras: series.valores(.cpuUso, periodo: dez, colunas: 16, agora: agora)),
            Bloco(modulo: .gpu, valor: gpu?.uso.map { Formato.percentual($0) } ?? s, quente: false,
                  sub: gpuSub.isEmpty ? s : gpuSub,
                  barras: series.valores(.gpuUso, periodo: dez, colunas: 16, agora: agora)),
            Bloco(modulo: .memoria, valor: mem.map { Formato.percentual($0.usadaPercentual) } ?? s, quente: false, sub: memSub,
                  barras: series.valores(.memUsada, periodo: dez, colunas: 16, agora: agora)),
            Bloco(modulo: .disco, valor: interno.map { Formato.percentual($0.ocupadoPercentual) } ?? s, quente: false,
                  sub: disco.map { "↓ \(Formato.velocidade($0.leituraBps)) · ↑ \(Formato.velocidade($0.escritaBps))" } ?? s,
                  barras: normalizar(series.valores(.discoLeitura, periodo: dez, colunas: 16, agora: agora))),
            Bloco(modulo: .rede, valor: rede?.conectado == true ? latencia : s, quente: false,
                  sub: rede.map { "↓ \(Formato.velocidade($0.baixandoBps)) · ↑ \(Formato.velocidade($0.enviandoBps))" } ?? s,
                  barras: normalizar(series.valores(.redeLatencia, janela: 120, colunas: 16, agora: agora))),
            Bloco(modulo: .sensores, valor: Formato.temperatura(sens?.cpuC, curta: false), quente: (sens?.cpuC ?? 0) >= 70,
                  sub: sistemaW.map { "CPU · sistema puxando \($0) W" } ?? "CPU",
                  barras: series.valores(.tempCPU, periodo: dez, colunas: 16, agora: agora)),
        ]
    }

    private var grade: some View {
        let b = blocos
        return VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { linha in
                HStack(spacing: 8) {
                    ForEach(0..<2, id: \.self) { col in cartaoModulo(b[linha * 2 + col]) }
                }
            }
        }
    }

    private func cartaoModulo(_ b: Bloco) -> some View {
        Button { acoes.abrirModulo(b.modulo) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(b.modulo.titulo)
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.7)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.primary.opacity(0.62))
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.45))
                }
                Text(b.valor)
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.5)
                    .monospacedDigit()
                    .foregroundStyle(b.quente ? AnyShapeStyle(estilo.destaqueTopo) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(b.sub)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                GraficoColunas(valores: b.barras.map { $0.map { max($0, 9) } }, maximo: 100, altura: 22, espaco: 2,
                               cor: { _, _ in estilo.destaque },
                               opacidade: { [n = b.barras.count] in $0 >= n - 4 ? 1 : 0.5 })
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.cartao))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(estilo.bordaCartao, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(b.modulo.titulo): \(b.valor)")
    }

    // MARK: Bateria

    private func subtituloBateria(_ s: Situacao) -> String {
        switch s.estado {
        case .parado: return "Na tomada · segurando em \(s.leitura.percentual)%"
        case .carregando:
            let adaptador = s.detalhes.adaptadorNome ?? s.detalhes.adaptadorW.map { "\(Int($0.rounded())) W" }
            return adaptador.map { "Carregando · \($0)" } ?? "Carregando"
        case .cheia: return "Na tomada · cheia"
        case .descarregando, .alto:
            return s.minutosAteFim.map { "Na bateria · \(Formato.duracaoLonga($0 * 60)) restantes" } ?? "Na bateria"
        }
    }

    private func cartaoBateria(_ s: Situacao) -> some View {
        Button(action: acoes.abrirBateria) {
            Cartao {
                HStack(spacing: 12) {
                    AnelModulo(fracao: Double(s.leitura.percentual) / 100, lado: 44, espessura: 5, cor: estilo.destaque,
                               centro: nil, sub: nil)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bateria")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(0.7)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.primary.opacity(0.62))
                        Text("\(Formato.percentual(s.leitura.percentual)) · \(Formato.ritmo(s.ritmoMedio))")
                            .font(.system(size: 18, weight: .bold))
                            .monospacedDigit()
                            .lineLimit(1)
                        Text(subtituloBateria(s))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(0.62))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.45))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Quem mais pesa

    private struct Pesado { var nome: String; var cpu: String; var mem: String }

    private var pesados: some View {
        let p = leituras.processos
        let memPorId = Dictionary(p.memoria.map { ($0.id, $0.valor) }, uniquingKeysWith: { a, _ in a })
        var linhas: [Pesado] = p.cpu.prefix(3).map {
            Pesado(nome: $0.nome, cpu: Formato.percentual($0.valor),
                   mem: memPorId[$0.id].map { Formato.bytesMemoria(UInt64(max($0, 0))) } ?? Formato.semDado)
        }
        if linhas.isEmpty {
            linhas = p.memoria.prefix(3).map {
                Pesado(nome: $0.nome, cpu: Formato.semDado, mem: Formato.bytesMemoria(UInt64(max($0.valor, 0))))
            }
        }
        return Group {
            if !linhas.isEmpty {
                VStack(spacing: 14) {
                    CabecalhoSecao("Quem mais pesa agora", dica: "CPU · memória").padding(.top, 2)
                    Cartao(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(linhas.indices, id: \.self) { i in linha(i, linhas[i]) }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func linha(_ i: Int, _ p: Pesado) -> some View {
        HStack(spacing: 10) {
            Text(String(p.nome.first.map { String($0).uppercased() } ?? "?"))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: "#1F1505"))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(hex: Self.coresLetra[i % 4])))
            Text(p.nome).font(.system(size: 14)).lineLimit(1)
            Spacer(minLength: 8)
            Text(p.cpu).font(.system(size: 14)).monospacedDigit().foregroundStyle(Color.primary.opacity(0.8))
            Text(p.mem).font(.system(size: 14)).monospacedDigit().foregroundStyle(Color.primary.opacity(0.62))
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }
}
