import SwiftUI

// Painel da Memória (docs/desenho/modulos/PainelMemoria.dc.html). O desenho não tem chips de período:
// a pressão mostra sempre a última 1 h; `periodoInicial` existe só para manter a assinatura dos painéis.

struct PainelMemoria: View {
    let leituras: LeiturasModulos
    let series: SeriesModulos
    let acoes: AcoesModulo
    var alturaMaxima: CGFloat? = nil
    var periodoInicial: PeriodoModulo = .dezMin
    @Environment(\.estilo) private var estilo

    private var agora: Date { leituras.data }
    private var mem: LeituraMemoria? { leituras.memoria }
    private static let gib = 1024.0 * 1024 * 1024

    var body: some View {
        MolduraPainelModulo(alturaMaxima: alturaMaxima) {
            CabecalhoModulo(icone: .memoria, titulo: "Memória", subtitulo: subtitulo, corPonto: corPressao,
                            rotuloPreferencias: "Preferências da memória", aoPreferencias: acoes.preferencias)
            cartaoEmUso
            cartaoPressao
            BlocosModulo(blocos)
            SecaoProcessosPainel(dica: "memória", itens: processos)
        } rodape: {
            RodapePainelModulo(modulo: .memoria, acoes: acoes)
        }
    }

    private var corPressao: Color {
        switch mem?.pressao {
        case .normal?: return Paleta.bom
        case .aviso?: return estilo.destaqueTopo
        case .critica?: return Color.quenteModulo
        case nil: return Color.primary.opacity(0.3)
        }
    }

    private var subtitulo: String {
        guard let mem else { return "Sem leitura" }
        return "Pressão \(mem.pressao.titulo.lowercased()) · \(Formato.bytesMemoria(mem.totalBytes))"
    }

    // MARK: Em uso

    private var partes: [(nome: String, bytes: UInt64, cor: Color)] {
        guard let mem else { return [] }
        return [
            ("Apps", mem.appsBytes, estilo.destaque),
            ("Fixa", mem.fixaBytes, Color(hex: "#F7E3B5")),
            ("Comprimida", mem.comprimidaBytes, Color(hex: "#9B7A3C")),
            ("Cache de arquivos", mem.cacheBytes, Color.primary.opacity(0.32)),
        ]
    }

    private var cartaoEmUso: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Em uso")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.9)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.primary.opacity(0.6))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(mem.map { Formato.numero(Double($0.usadaBytes) / Self.gib, casas: 1) } ?? Formato.semDado)
                            .font(.system(size: 46, weight: .bold)).tracking(-1.4)
                            .foregroundStyle(estilo.destaqueTopo)
                        if let mem {
                            Text("de " + Formato.bytesMemoria(mem.totalBytes))
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.primary.opacity(0.75))
                        }
                    }
                    .monospacedDigit()
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(mem.map { Formato.percentual($0.usadaPercentual) } ?? Formato.semDado)
                    .font(.system(size: 22, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Color.primary.opacity(0.8))
                    .padding(.bottom, 6)
            }
            if let mem, mem.totalBytes > 0 {
                let total = Double(mem.totalBytes)
                BarraSegmentos(partes: partes.map { (Double($0.bytes) / total, $0.cor) }, altura: 12)
                LegendaSegmentos(itens: partes.map { ($0.cor, $0.nome, Formato.bytesMemoria($0.bytes)) }, colunas: 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(estilo.cartao))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(estilo.bordaCartao, lineWidth: 1))
    }

    // MARK: Pressão

    private var textoPressao: String {
        guard let mem else { return Formato.semDado }
        var t = mem.pressao.titulo
        if let p = mem.pressaoPercentual { t += " · " + Formato.percentual(p) }
        return t
    }

    private var cartaoPressao: some View {
        Cartao(padding: 0) {
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    RotuloSecao("Pressão de memória")
                    Spacer(minLength: 8)
                    Text(textoPressao).font(.system(size: 14, weight: .bold)).foregroundStyle(corPressao)
                }
                // O desenho usa 2,2 vezes a altura (v / 100 * 70 * 2,2): a escala vai a ~45%.
                GraficoColunas(valores: series.valores(.memPressao, periodo: .umaHora, colunas: 30, agora: agora),
                               maximo: 100 / 2.2, altura: 70,
                               cor: { _, v in v >= 30 ? estilo.destaqueTopo : Paleta.bom }, opacidade: { _ in 0.85 })
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1) }
                EixoTempo(["há 1 h", "agora"])
                Text("É o número que importa no Mac: memória cheia com pressão baixa é cache trabalhando, não falta de memória.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.62))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(EdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12))
        }
    }

    // MARK: Blocos e processos

    private var blocos: [(rotulo: String, valor: String, sub: String)] {
        [
            ("Swap", mem.map { Formato.bytesMemoria($0.swapUsadoBytes) } ?? Formato.semDado, "em uso"),
            ("Livre", mem.map { Formato.bytesMemoria($0.livreBytes) } ?? Formato.semDado, "de verdade"),
            ("Desde que ligou", leituras.ligadoDesde.map { Formato.duracaoLonga(agora.timeIntervalSince($0)) } ?? Formato.semDado,
             "sem reiniciar"),
        ]
    }

    private var processos: [(nome: String, valor: String, fracao: Double?)] {
        leituras.processos.memoria.prefix(5).map { ($0.nome, Formato.bytesMemoria(UInt64(max($0.valor, 0))), $0.fracao) }
    }
}
