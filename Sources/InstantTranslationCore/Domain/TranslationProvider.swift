import Foundation

public enum TranslationProviderError: Error, Equatable, Sendable {
    case unconfigured
    case invalidCredentials
    case rateLimited
    case networkUnavailable
    case timedOut
    case insecureEndpoint
    case invalidResponse
    case server(statusCode: Int)
    case cancelled
}

public protocol TranslationProvider: Sendable {
    var id: ProviderID { get }
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
}

/// 按需补充语境的能力，单独成一个协议而不是加宽 TranslationProvider——
/// Google 和各处测试替身都翻译，但都没有也不需要这个方法。
public protocol ContextExpansionProvider: Sendable {
    func expandContext(
        for request: TranslationRequest,
        excluding existingResult: TranslationResult
    ) async throws -> ContextExpansionResult
}
