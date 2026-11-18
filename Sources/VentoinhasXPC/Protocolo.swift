import Foundation

/// Nomes e regras comuns ao app e ao ajudante das ventoinhas.
public enum Ventoinhas {
    /// Serviço Mach do ajudante (o mesmo `Label` e `MachServices` do plist em Contents/Library/LaunchDaemons).
    public static let servico = "com.edufigueiredo.consumobateria.ventoinhas"
    /// Nome do plist que o app registra com `SMAppService.daemon(plistName:)`.
    public static let plist = servico + ".plist"
    /// Só o My Stats assinado com o Developer ID do Eduardo conversa com o ajudante.
    public static let requisitoApp =
        #"anchor apple generic and identifier "com.edufigueiredo.consumobateria" and certificate leaf[subject.OU] = "2MQDBK8S36""#
    /// E o app só conversa com o ajudante assinado do mesmo jeito.
    public static let requisitoAjudante =
        #"anchor apple generic and identifier "com.edufigueiredo.consumobateria.ventoinhas" and certificate leaf[subject.OU] = "2MQDBK8S36""#
    /// Alvo negativo: devolve aquela ventoinha ao macOS.
    public static let automatico: Double = -1
}

/// O que o app pede ao ajudante. Os alvos valem só por `validoPor` segundos: se o app não renovar (fechou, travou,
/// o Mac dormiu), o ajudante devolve as ventoinhas ao macOS sozinho.
@objc public protocol ProtocoloVentoinhas {
    /// Versão (CFBundleVersion) do app de onde o ajudante foi aberto.
    func versao(resposta: @escaping (String) -> Void)
    /// `rpm[i]` para a ventoinha i: 0 para, valor positivo gira (limitado ao mínimo e ao máximo dela),
    /// `Ventoinhas.automatico` devolve ao macOS. Resposta: nil se deu certo, ou o erro.
    func definir(rpm: [NSNumber], validoPor: Double, resposta: @escaping (String?) -> Void)
    /// Todas as ventoinhas de volta ao macOS.
    func automatico(resposta: @escaping (String?) -> Void)
    /// Devolve as ventoinhas ao macOS e encerra (o launchd abre a versão nova no próximo pedido).
    func encerrar()
}
