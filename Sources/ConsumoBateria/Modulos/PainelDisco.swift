import SwiftUI

// Painel do módulo Disco (docs/desenho/modulos/PainelDisco.dc.html). Dados de LeiturasModulos/SeriesModulos.

struct PainelDisco: View {
    @Environment(\.estilo) private var estilo
    let leituras: LeiturasModulos
    let series: SeriesModulos
    let acoes: AcoesModulo
    var alturaMaxima: CGFloat? = nil

    private var disco: LeituraDisco? { leituras.disco }

    var body: some View {
        MolduraPainelModulo(alturaMaxima: alturaMaxima) {
            CabecalhoModulo(icone: .disco, titulo: "Disco", subtitulo: subtitulo, corPonto: Paleta.bom,
                            rotuloPreferencias: "Preferências do disco", aoPreferencias: acoes.preferencias)

            if let disco {
                ForEach(Array(disco.volumes.enumerated()), id: \.element.id) { i, volume in
                    cartaoVolume(volume, primeiroInterno: volume.id == primeiroInternoID(disco))
                    let _ = i
                }
            }

            HStack(spacing: 8) {
                tile(rotulo: "Lendo", cor: estilo.destaque, valor: disco.map { Formato.velocidade($0.leituraBps) } ?? Formato.semDado)
                tile(rotulo: "Gravando", cor: Color.primary.opacity(0.5), valor: disco.map { Formato.velocidade($0.escritaBps) } ?? Formato.semDado)
            }

            graficoCartao

            if let linhas = linhasSaude {
                CabecalhoSecao("Saúde do SSD").padding(.top, 2)
                CartaoLinhas(linhas)
            }

            if !leituras.processos.disco.isEmpty {
                CabecalhoSecao("Quem mais lê e grava", dica: "últimos 10 s").padding(.top, 2)
                Cartao(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(leituras.processos.disco.enumerated()), id: \.element.id) { i, p in
                            LinhaProcesso(indice: i, nome: p.nome,
                                          valor: "↓ \(Formato.velocidade(p.valor)) · ↑ \(Formato.velocidade(p.valor2 ?? 0))",
                                          fracao: p.fracao)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
            }
        } rodape: {
            RodapeModulo(tituloBotao: Modulo.disco.tituloAbrirApp, acaoBotao: acoes.abrirApp,
                         textoEsquerda: "Visão geral", acaoEsquerda: acoes.visaoGeral, sair: acoes.sair)
        }
    }

    // MARK: Cabeçalho

    private var subtitulo: String {
        let n = disco?.volumes.count ?? 0
        var t = n == 1 ? "1 volume" : "\(n) volumes"
        if let vida = disco?.saude?.vidaUsadaPercentual, vida < 10 { t += " · SSD saudável" }
        return t
    }

    // MARK: Volumes

    private func primeiroInternoID(_ d: LeituraDisco) -> String? { d.volumes.first(where: { $0.interno })?.id }

    private func cartaoVolume(_ v: VolumeDisco, primeiroInterno: Bool) -> some View {
        let usado = v.totalBytes - min(v.livreBytes, v.totalBytes)
        let total = max(Double(v.totalBytes), 1)
        let fracUsado = Double(usado) / total
        let fracPurgavel = min(Double(v.purgavelBytes) / total, max(1 - fracUsado, 0))
        let corUsado = v.interno ? estilo.destaque : Color.white.opacity(0.6)
        return Cartao(padding: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(v.nome).font(.system(size: 15, weight: .bold))
                    Spacer(minLength: 8)
                    Text(v.tipo).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.62))
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Formato.percentual(v.ocupadoPercentual))
                        .font(.system(size: primeiroInterno ? 34 : 26, weight: .bold))
                        .tracking(primeiroInterno ? -0.7 : -0.5)
                        .foregroundStyle(primeiroInterno ? estilo.destaqueTopo : Color.primary)
                    Text(detalhe(usado: usado, total: v.totalBytes))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.primary.opacity(0.7))
                }
                .monospacedDigit()
                BarraSegmentos(partes: [(fracUsado, corUsado), (fracPurgavel, estilo.destaque.opacity(0.35))], altura: 8)
                rodapeVolume(v)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    /// "437 de 994 GB": a unidade do primeiro número some quando é a mesma do total.
    private func detalhe(usado: UInt64, total: UInt64) -> String {
        let a = Formato.bytesDisco(usado), b = Formato.bytesDisco(total)
        let ua = a.split(separator: " ").last.map(String.init) ?? "", ub = b.split(separator: " ").last.map(String.init) ?? ""
        let curto = ua == ub ? String(a.dropLast(ua.count + 1)) : a
        return "\(curto) de \(b)"
    }

    @ViewBuilder
    private func rodapeVolume(_ v: VolumeDisco) -> some View {
        let livres = "\(Formato.bytesDisco(v.livreBytes)) livres"
        let fonte = Font.system(size: 12)
        let cor = Color.primary.opacity(0.62)
        if v.ejetavel {
            HStack(spacing: 0) {
                Text(livres + " · ").font(fonte).foregroundStyle(cor)
                Button { acoes.ejetar(v.url) } label: {
                    Text("Ejetar").font(.system(size: 12, weight: .semibold)).foregroundStyle(estilo.destaqueTopo)
                        .frame(minHeight: 20)
                }
                .buttonStyle(.plain)
            }
        } else if v.purgavelBytes > 0 {
            Text("\(livres) · \(Formato.bytesDisco(v.purgavelBytes)) podem ser liberados pelo macOS").font(fonte).foregroundStyle(cor)
        } else {
            Text(livres).font(fonte).foregroundStyle(cor)
        }
    }

    // MARK: Velocidade

    private func tile(rotulo: String, cor: Color, valor: String) -> some View {
        Cartao(padding: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(cor).frame(width: 8, height: 8)
                    Text(rotulo).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.62))
                }
                Text(valor).font(.system(size: 22, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    private var graficoCartao: some View {
        let agora = leituras.data
        let leitura = series.valores(.discoLeitura, periodo: .dezMin, colunas: 30, agora: agora)
        let escrita = series.valores(.discoEscrita, periodo: .dezMin, colunas: 30, agora: agora)
        // Escalas do desenho: 100 MB/s enche os 54 pt de cima; 56,7 MB/s enche os 34 pt de baixo.
        let maxCima = max(100e6, leitura.compactMap { $0 }.max() ?? 0)
        let maxBaixo = max(56.67e6, escrita.compactMap { $0 }.max() ?? 0)
        return Cartao(padding: 12) {
            VStack(spacing: 0) {
                GraficoEspelhado(cima: leitura, baixo: escrita, maximoCima: maxCima, maximoBaixo: maxBaixo, alturaCima: 54, alturaBaixo: 34)
                EixoTempo(["há 10 min", "agora"]).padding(.top, 4)
            }
        }
    }

    // MARK: Saúde

    private var linhasSaude: [(String, String)]? {
        let s = disco?.saude
        let temp = s?.temperaturaC ?? leituras.sensores?.ssdC
        if s?.vidaUsadaPercentual == nil, s?.gravadoBytes == nil, s?.erros == nil, temp == nil { return nil }
        return [
            ("Vida útil usada", s?.vidaUsadaPercentual.map { Formato.percentual($0) } ?? Formato.semDado),
            ("Já gravado", s?.gravadoBytes.map { Formato.bytesDisco($0) } ?? Formato.semDado),
            ("Temperatura", Formato.temperatura(temp, curta: false)),
            ("Erros", s?.erros.map { $0 == 0 ? "nenhum" : Formato.inteiro($0) } ?? Formato.semDado),
        ]
    }
}
