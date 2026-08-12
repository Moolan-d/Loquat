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
