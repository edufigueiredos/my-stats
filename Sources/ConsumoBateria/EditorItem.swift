import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Painéis do editor do item: "Ajustes do item" (por estado) e "Meus formatos" (formatos salvos).
// Controles desenhados à mão: Slider, Toggle, Picker, Stepper e Menu nativos somem no ImageRenderer do --foto.

// MARK: - Regulador e chave desenhados

/// Regulador desenhado (o Slider nativo some no ImageRenderer).
struct ReguladorFino: View {
    @Environment(\.estilo) private var estilo
    let valor: Double
    let faixa: ClosedRange<Double>
    let passo: Double
    var ativo = true
    let aoMudar: (Double) -> Void

    private let botao: CGFloat = 16

    var body: some View {
        GeometryReader { g in
            let util = max(1, g.size.width - botao)
            let f = (valor - faixa.lowerBound) / (faixa.upperBound - faixa.lowerBound)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color.primary.opacity(0.15)).frame(height: 4)
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(estilo.destaque.opacity(ativo ? 1 : 0.35))
                    .frame(width: botao / 2 + util * f, height: 4)
                Circle().fill(Color.white).frame(width: botao, height: botao)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.2), lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    .offset(x: util * f)
                    .opacity(ativo ? 1 : 0.6)
            }
            .frame(height: g.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let t = min(1, max(0, (v.location.x - botao / 2) / util))
                let bruto = faixa.lowerBound + t * (faixa.upperBound - faixa.lowerBound)
                aoMudar(min(faixa.upperBound, max(faixa.lowerBound, (bruto / passo).rounded() * passo)))
            })
        }
        .frame(height: 22)
    }
}

/// Chave liga/desliga desenhada.
struct ChaveFina: View {
    @Environment(\.estilo) private var estilo
    let ligado: Bool
    let aoMudar: (Bool) -> Void

    var body: some View {
        Button { aoMudar(!ligado) } label: {
            ZStack(alignment: ligado ? .trailing : .leading) {
                if ligado {
                    if estilo.ehNeon {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.destaque.opacity(0.25))
                        RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(estilo.destaque, lineWidth: 1.5)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estilo.degrade)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.18))
                }
                Circle().fill(Color.white).frame(width: 20, height: 20).padding(2)
            }
            .frame(width: 40, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(ligado ? .isSelected : [])
    }
}

// MARK: - Ajustes do item

/// Ajustes do item inteiro de um estado: espaçamento, alinhamento, largura, fonte, tamanho, fundo, faixas e ocultar.
struct PainelItemEstado: View {
    @Environment(\.estilo) private var estilo
    let config: ConfigEstado
    let estado: EstadoBarra
    let cores: [String]
    var paraFoto = false
    let mudar: (ConfigEstado) -> Void

    private func alterar(_ f: (inout ConfigEstado) -> Void) {
        var novo = config
        f(&novo)
        mudar(novo)
    }

    private func numero(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "pt_BR")))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ajustes do item").font(.system(size: 15, weight: .bold))
                Text(estado.titulo).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            campo("Espaço entre peças") {
                HStack(spacing: 8) {
                    chip("Automático", selecionado: config.espacoPecas == nil) { alterar { $0.espacoPecas = nil } }
                    ReguladorFino(valor: config.espacoPecas ?? 4, faixa: 0...12, passo: 0.5, ativo: config.espacoPecas != nil) { v in
                        alterar { $0.espacoPecas = v }
                    }
                    Text(config.espacoPecas.map { numero($0) + " pt" } ?? "auto")
                        .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                        .foregroundStyle(config.espacoPecas == nil ? Color.secondary : Color.primary)
                }
            }
            campo("Alinhamento vertical") {
                HStack(spacing: 6) {
                    ForEach(AlinhamentoVertical.allCases) { a in
                        let sel = a == config.alinhamentoVertical
                        Button { alterar { $0.alinhamentoVertical = a } } label: {
                            HStack(spacing: 5) {
                                Image(systemName: a.simbolo).font(.system(size: 11, weight: .semibold))
                                Text(a.titulo).font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(sel ? estilo.primeiroPlanoSelecionado : Color.primary.opacity(0.75))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(FundoSelecionavel(selecionado: sel, capsula: true))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Alinhar \(a.titulo.lowercased())")
                        .accessibilityAddTraits(sel ? .isSelected : [])
                    }
                }
            }
            campo("Largura mínima") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        chip("Do conteúdo", selecionado: config.larguraMinima == nil) { alterar { $0.larguraMinima = nil } }
                        ReguladorFino(valor: config.larguraMinima ?? 60, faixa: 20...200, passo: 2, ativo: config.larguraMinima != nil) { v in
                            alterar { $0.larguraMinima = v }
                        }
                        Text(config.larguraMinima.map { numero($0) + " pt" } ?? "auto")
                            .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                            .foregroundStyle(config.larguraMinima == nil ? Color.secondary : Color.primary)
                    }
                    dica("com largura fixa o número não faz a barra pular e o alinhamento passa a valer")
                }
            }
            campo("Fonte") {
                LinhaChips(opcoes: FonteItem.allCases.map { .init(valor: $0, titulo: $0.titulo) },
                           selecao: config.fonte) { v in alterar { $0.fonte = v } }
                    .padding(3)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(estilo.ladrilho))
            }
            campo("Tamanho geral") {
                HStack(spacing: 8) {
                    ReguladorFino(valor: (config.tamanhoGeral * 100).rounded(), faixa: 70...130, passo: 5,
                                  ativo: abs(config.tamanhoGeral - 1) > 0.001) { v in
                        alterar { $0.tamanhoGeral = v / 100 }
                    }
                    Text("\(Int((config.tamanhoGeral * 100).rounded())) %")
                        .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
            }
            campo("Fundo") {
                VStack(alignment: .leading, spacing: 8) {
                    LinhaChips(opcoes: FundoItem.allCases.map { .init(valor: $0, titulo: $0.titulo) },
                               selecao: config.fundo) { v in alterar { $0.fundo = v } }
                        .padding(3)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(estilo.ladrilho))
                    if config.fundo != .nenhum {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Cor do fundo").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                            chip("Do estado", selecionado: config.corFundoHex == nil) { alterar { $0.corFundoHex = nil } }
                            bolinhas(selecionada: config.corFundoHex) { hex in alterar { $0.corFundoHex = hex } }
                        }
                    }
                }
            }
            campo("Cor por faixa") { faixas }
            campo("Esconder neste estado") {
                VStack(alignment: .leading, spacing: 6) {
                    ChaveFina(ligado: config.oculto) { v in alterar { $0.oculto = v } }
                    dica("vira um ponto discreto; o clique continua abrindo o painel")
                }
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    // MARK: Faixas

    private var faixas: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(config.faixas) { f in linhaFaixa(f) }
            if config.faixas.count < 4 {
                Button {
                    alterar {
                        $0.faixas.append(FaixaCor(medida: .ritmo, comparacao: .acimaDe, limite: 10,
                                                  corHex: cores.first ?? "#FF9F0A"))
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        Text("Acrescentar faixa").font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(estilo.ladrilho))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Acrescentar faixa")
            }
            dica("a primeira faixa que valer troca a cor do estado")
        }
    }

    private func linhaFaixa(_ f: FaixaCor) -> some View {
        let faixaLimite: ClosedRange<Double> = f.medida == .ritmo ? 1...60 : 1...100
        let unidade = f.medida == .ritmo ? "%/h" : "%"
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                LinhaChips(opcoes: MedidaFaixa.allCases.map { .init(valor: $0, titulo: $0.titulo) },
                           selecao: f.medida) { v in
                    alterarFaixa(f.id) { $0.medida = v; $0.limite = min(max($0.limite, v == .ritmo ? 1 : 1), v == .ritmo ? 60 : 100) }
                }
                Button { alterar { c in c.faixas.removeAll { $0.id == f.id } } } label: {
                    Image(systemName: "trash").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "#FF453A"))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(estilo.ladrilho))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Apagar faixa")
            }
            HStack(spacing: 6) {
                LinhaChips(opcoes: ComparacaoFaixa.allCases.map { .init(valor: $0, titulo: $0.titulo) },
                           selecao: f.comparacao) { v in alterarFaixa(f.id) { $0.comparacao = v } }
                botaoPasso("minus", rotulo: "Diminuir limite") {
                    alterarFaixa(f.id) { $0.limite = min(faixaLimite.upperBound, max(faixaLimite.lowerBound, $0.limite - 1)) }
                }
                Text(numero(f.limite) + " " + unidade)
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    .frame(minWidth: 52)
                botaoPasso("plus", rotulo: "Aumentar limite") {
                    alterarFaixa(f.id) { $0.limite = min(faixaLimite.upperBound, max(faixaLimite.lowerBound, $0.limite + 1)) }
                }
            }
            bolinhas(selecionada: f.corHex) { hex in alterarFaixa(f.id) { $0.corHex = hex } }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(estilo.ladrilho.opacity(0.6)))
    }

    private func alterarFaixa(_ id: UUID, _ f: (inout FaixaCor) -> Void) {
        alterar { c in
            guard let i = c.faixas.firstIndex(where: { $0.id == id }) else { return }
            f(&c.faixas[i])
        }
    }

    // MARK: Peças visuais

    private func bolinhas(selecionada: String?, _ escolher: @escaping (String) -> Void) -> some View {
        HStack(spacing: 5) {
            ForEach(cores, id: \.self) { hex in
                let sel = hex.uppercased() == selecionada?.uppercased()
                Button { escolher(hex) } label: {
                    Circle().fill(Color(hex: hex)).frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(sel ? estilo.destaque : Color.primary.opacity(0.25), lineWidth: sel ? 2.5 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cor \(hex)")
            }
        }
    }

    private func botaoPasso(_ simbolo: String, rotulo: String, acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: simbolo).font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(estilo.ladrilho))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rotulo)
    }

    private func dica(_ texto: String) -> some View {
        Text(texto).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func campo<C: View>(_ nome: String, @ViewBuilder _ conteudo: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(nome).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            conteudo().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chip(_ titulo: String, selecionado: Bool, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Text(titulo)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selecionado ? estilo.primeiroPlanoSelecionado : Color.primary.opacity(0.75))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(FundoSelecionavel(selecionado: selecionado, capsula: true))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selecionado ? .isSelected : [])
    }
}

// MARK: - Meus formatos

/// Formatos salvos pelo usuário: salvar a montagem atual, aplicar, renomear, exportar, apagar e importar.
struct SecaoMeusFormatos: View {
    @Environment(\.estilo) private var estilo
    var ajustes: Ajustes
    var casas: Int
    var sentido: SentidoRitmo
    var paraFoto = false
    var antesDeMudar: () -> Void = {}

    @State private var nomeNovo = ""
    @State private var mensagem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Meus formatos").font(.system(size: 15, weight: .bold))
                Text("Guarde a montagem de todos os estados com um nome e volte a ela quando quiser.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                campoNome
                Button { salvar() } label: {
                    Text("Salvar a montagem atual")
                }
                .buttonStyle(EstiloBotaoDestaque())
            }
            if ajustes.formatosSalvos.isEmpty {
                Text("Nenhum formato salvo ainda").font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 10)
            } else {
                VStack(spacing: 8) {
                    ForEach(ajustes.formatosSalvos) { f in
                        LinhaFormatoSalvo(formato: f, ajustes: ajustes, casas: casas, sentido: sentido, paraFoto: paraFoto,
                                          aplicar: { antesDeMudar(); ajustes.aplicarSalvo(f); mensagem = "“\(f.nome)” aplicado" },
                                          exportar: { exportar([f]) })
                    }
                }
            }
            HStack(spacing: 8) {
                botao("Exportar todos…", "square.and.arrow.up", ativo: !ajustes.formatosSalvos.isEmpty) {
                    exportar(ajustes.formatosSalvos)
                }
                botao("Importar…", "square.and.arrow.down", ativo: true) { importar() }
            }
            if let mensagem {
                Text(mensagem).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var campoNome: some View {
        if paraFoto {
            Text("Nome do formato").font(.system(size: 13)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(estilo.ladrilho))
        } else {
            TextField("Nome do formato", text: $nomeNovo)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(estilo.ladrilho))
                .onSubmit { salvar() }
        }
    }

    private func salvar() {
        if let recusa = ajustes.salvarFormatoAtual(nome: nomeNovo) {
            mensagem = recusa
        } else {
            nomeNovo = ""
            mensagem = "Formato salvo"
        }
    }

    private func botao(_ titulo: String, _ simbolo: String, ativo: Bool, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            HStack(spacing: 6) {
                Image(systemName: simbolo).font(.system(size: 11, weight: .semibold))
                Text(titulo).font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(estilo.ladrilho))
            .opacity(ativo ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!ativo)
        .accessibilityLabel(titulo)
    }

    private func exportar(_ formatos: [FormatoSalvo]) {
        let painel = NSSavePanel()
        painel.allowedContentTypes = [.json]
        painel.nameFieldStringValue = "formatos-barra.json"
        guard painel.runModal() == .OK, let url = painel.url else { return }
        do {
            try ajustes.exportarJSON(formatos).write(to: url, options: .atomic)
            mensagem = formatos.count == 1 ? "1 formato exportado" : "\(formatos.count) formatos exportados"
        } catch {
            mensagem = error.localizedDescription
        }
    }

    private func importar() {
        let painel = NSOpenPanel()
        painel.allowedContentTypes = [.json]
        painel.allowsMultipleSelection = false
        painel.canChooseDirectories = false
        guard painel.runModal() == .OK, let url = painel.url else { return }
        do {
            let tamanho = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            guard tamanho <= 512 * 1024 else { throw Ajustes.ErroImportacao.grandeDemais }
            let dados = try Data(contentsOf: url)
            mensagem = try ajustes.importarJSON(dados).mensagem
        } catch {
            mensagem = error.localizedDescription
        }
    }
}

/// Uma linha da lista: prévia, nome e as ações.
private struct LinhaFormatoSalvo: View {
    @Environment(\.estilo) private var estilo
    let formato: FormatoSalvo
    var ajustes: Ajustes
    let casas: Int
    let sentido: SentidoRitmo
    let paraFoto: Bool
    let aplicar: () -> Void
    let exportar: () -> Void

    @State private var renomeando = false
    @State private var nomeEditado = ""
    @State private var confirmandoApagar = false

    private var estadoPrevia: EstadoBarra? {
        if formato.config(.descarregando) != nil { return .descarregando }
        return EstadoBarra.allCases.first { formato.config($0) != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                previa
                VStack(alignment: .leading, spacing: 2) {
                    if renomeando { campoRenomear } else {
                        Text(formato.nome).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    }
                    Text(formato.configs.count == 1 ? "1 estado" : "\(formato.configs.count) estados")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                acao("Aplicar", "checkmark", destaque: true) { confirmandoApagar = false; aplicar() }
                acao(renomeando ? "Salvar" : "Renomear", "pencil") { confirmandoApagar = false; renomearOuSalvar() }
                acao("Exportar", "square.and.arrow.up") { confirmandoApagar = false; exportar() }
                acao(confirmandoApagar ? "Confirmar" : "Apagar", "trash", vermelho: true) {
                    if confirmandoApagar { ajustes.apagarSalvo(id: formato.id) } else { confirmandoApagar = true }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(estilo.cartao))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(estilo.bordaCartao, lineWidth: 1))
        .task(id: confirmandoApagar) {
            // A confirmação some sozinha depois de ~4 s.
            guard confirmandoApagar else { return }
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { confirmandoApagar = false }
        }
    }

    @ViewBuilder
    private var previa: some View {
        Group {
            if let e = estadoPrevia, let cfg = formato.config(e) {
                VistaItemBarra(situacao: .exemplo(e), config: cfg, colorir: true, casas: casas,
                               sentido: sentido, escala: 1, corBase: .white)
            } else {
                Text("Sem prévia").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .frame(minWidth: 84, minHeight: 30)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.6)))
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var campoRenomear: some View {
        if paraFoto {
            Text(nomeEditado).font(.system(size: 13, weight: .semibold))
        } else {
            TextField("Nome", text: $nomeEditado)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(estilo.ladrilho))
                .onSubmit { renomearOuSalvar() }
        }
    }

    private func renomearOuSalvar() {
        if renomeando {
            ajustes.renomearSalvo(id: formato.id, nome: nomeEditado)
            renomeando = false
        } else {
            nomeEditado = formato.nome
            renomeando = true
        }
    }

    private func acao(_ titulo: String, _ simbolo: String, destaque: Bool = false, vermelho: Bool = false,
                      _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            HStack(spacing: 4) {
                Image(systemName: simbolo).font(.system(size: 10, weight: .semibold))
                Text(titulo).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(destaque ? estilo.primeiroPlanoSelecionado
                             : (vermelho ? Color(hex: "#FF453A") : Color.primary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if destaque { FundoSelecionavel(selecionado: true, capsula: true) }
                else { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(estilo.ladrilho) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(titulo)
    }
}
