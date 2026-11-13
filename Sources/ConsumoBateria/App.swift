import SwiftUI
import Charts

@main
enum Entrada {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--foto"), i + 1 < args.count {
            MainActor.assumeIsolated { Foto.gerar(em: args[i + 1]) }
            return
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { ConsumoBateriaApp.monitorCompartilhado.salvar() } }
        ConsumoBateriaApp.main()
    }
}

/// Desenha o painel num PNG (para conferir o visual sem abrir o menu).
@MainActor
enum Foto {
    static func gerar(em caminho: String) {
        let monitor = Monitor(vivo: false)
        let vista = VStack(spacing: 0) {
            // Faixa imitando a barra de menus, com o mesmo texto que vai lá.
            HStack(spacing: 14) {
                Spacer()
                Text(Formato.ritmo(monitor.ritmoMedio)).monospacedDigit()
                Image(systemName: "wifi")
                Text("13:30")
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(width: 300, height: 24)
            .background(Color.black.opacity(0.85))
            PainelView(monitor: monitor, paraFoto: true)
                .background(Color(nsColor: .windowBackgroundColor))
        }
            .environment(\.colorScheme, .dark)
        let r = ImageRenderer(content: vista)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("falhou"); return
        }
        try? png.write(to: URL(fileURLWithPath: caminho))
        print("ok: \(caminho)  barra: \(Formato.ritmo(monitor.ritmoMedio))")
    }
}

struct ConsumoBateriaApp: App {
    @MainActor static let monitorCompartilhado = Monitor()
    @State private var monitor = ConsumoBateriaApp.monitorCompartilhado

    var body: some Scene {
        MenuBarExtra {
            PainelView(monitor: monitor)
        } label: {
            Text(Formato.ritmo(monitor.ritmoMedio))
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}

struct PainelView: View {
    @Bindable var monitor: Monitor
    var paraFoto = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let b = monitor.atual {
                cabecalho(b)
                Divider()
                detalhes(b)
                Divider()
                grafico
                Divider()
                rodape
            } else {
                Text("Não encontrei a bateria deste Mac.")
                    .foregroundStyle(.secondary)
                rodape
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private func cabecalho(_ b: LeituraBateria) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Formato.ritmo(monitor.ritmoMedio))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(legendaMedia)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(b.percentual) %")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Text(estado(b))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var legendaMedia: String {
        let min = monitor.minutosNaMedia
        if min < 1 { return "média: juntando amostras" }
        if min >= Monitor.janelaMedia / 60 - 0.5 { return "média dos últimos 10 min" }
        return "média de \(Int(min.rounded())) min"
    }

    private func estado(_ b: LeituraBateria) -> String {
        if b.cheia { return "cheia" }
        if b.carregando { return "carregando" }
        if b.naTomada { return "na tomada" }
        return "na bateria"
    }

    private func detalhes(_ b: LeituraBateria) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
            linha("Agora", Formato.ritmo(b.ritmoInstantaneo))
            linha(b.correnteMa > 0 ? "Até encher" : "Tempo restante", tempoRestante(b))
            linha("Potência", "\(Formato.comSinal(b.watts)) W")
            linha("Corrente", "\(Formato.comSinal(Double(b.correnteMa), casas: 0)) mA")
            linha("Tensão", "\(Formato.numero(Double(b.tensaoMv) / 1000, casas: 2)) V")
            linha("Carga", "\(Formato.numero(Double(b.cargaMah), casas: 0)) de \(Formato.numero(Double(b.capacidadeMah), casas: 0)) mAh")
        }
        .font(.callout)
    }

    private func tempoRestante(_ b: LeituraBateria) -> String {
        let proprio = Formato.duracao(minutos: monitor.minutosEstimados)
        guard let sistema = b.minutosSistema else { return proprio }
        let s = Formato.duracao(minutos: Double(sistema))
        return proprio == "–" ? "\(s) (sistema)" : "\(proprio)  ·  sistema \(s)"
    }

    private func linha(_ nome: String, _ valor: String) -> some View {
        GridRow {
            Text(nome).foregroundStyle(.secondary)
            Text(valor).monospacedDigit()
                .gridColumnAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var grafico: some View {
        let agora = monitor.atual?.data ?? Date()
        return VStack(alignment: .leading, spacing: 4) {
            Text("Última hora (%/h)")
                .font(.caption)
                .foregroundStyle(.secondary)
            let cor: Color = (monitor.ritmoMedio ?? 0) > 0 ? .green : .orange
            Chart {
                ForEach(monitor.amostras) { a in
                    AreaMark(x: .value("Hora", a.data), y: .value("%/h", a.ritmo))
                        .foregroundStyle(cor.opacity(0.22))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Hora", a.data), y: .value("%/h", a.ritmo))
                        .foregroundStyle(cor)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.monotone)
                }
                if let media = monitor.ritmoMedio {
                    RuleMark(y: .value("Média", media))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXScale(domain: agora.addingTimeInterval(-Monitor.janelaGrafico)...agora)
            .chartXAxis {
                AxisMarks(values: marcasDeHora(ate: agora)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .frame(height: 110)
        }
    }

    /// Marcas a cada 15 min em horários redondos (13:00, 13:15...).
    private func marcasDeHora(ate agora: Date) -> [Date] {
        let cal = Calendar.current
        let inicio = agora.addingTimeInterval(-Monitor.janelaGrafico)
        var c = cal.dateComponents([.year, .month, .day, .hour], from: inicio)
        c.minute = 0
        guard var d = cal.date(from: c) else { return [] }
        var marcas: [Date] = []
        // Sem marca colada na borda direita, onde o rótulo seria cortado.
        while d <= agora.addingTimeInterval(-4 * 60) {
            if d >= inicio { marcas.append(d) }
            d = d.addingTimeInterval(15 * 60)
        }
        return marcas
    }

    private var rodape: some View {
        HStack {
            if paraFoto {
                Text("☐ Abrir ao iniciar o Mac")
                Spacer()
                Text("Sair")
            } else {
            Toggle("Abrir ao iniciar o Mac", isOn: Binding(
                get: { monitor.abrirAoIniciar },
                set: { monitor.alternarAbrirAoIniciar($0) }
            ))
            .toggleStyle(.checkbox)
            Spacer()
            Button("Sair") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
            }
        }
        .font(.callout)
    }
}
