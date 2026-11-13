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
            linha("Potência", "\(Formato.numero(b.watts)) W")
            linha("Corrente", "\(b.correnteMa) mA")
            linha("Tensão", "\(Formato.numero(Double(b.tensaoMv) / 1000, casas: 2)) V")
            linha("Carga", "\(b.cargaMah) de \(b.capacidadeMah) mAh")
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
            Chart {
                ForEach(monitor.amostras) { a in
                    AreaMark(x: .value("Hora", a.data), y: .value("%/h", a.ritmo))
                        .foregroundStyle(a.ritmo < 0 ? Color.orange.opacity(0.25) : Color.green.opacity(0.25))
                    LineMark(x: .value("Hora", a.data), y: .value("%/h", a.ritmo))
                        .foregroundStyle(a.ritmo < 0 ? Color.orange : Color.green)
                        .lineStyle(StrokeStyle(lineWidth: 1.2))
                }
                if let media = monitor.ritmoMedio {
                    RuleMark(y: .value("Média", media))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXScale(domain: agora.addingTimeInterval(-Monitor.janelaGrafico)...agora)
            .chartXAxis {
                AxisMarks(values: .stride(by: .minute, count: 15)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .frame(height: 110)
        }
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
