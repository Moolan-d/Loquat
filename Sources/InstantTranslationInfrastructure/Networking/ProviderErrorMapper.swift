import Foundation
import InstantTranslationCore

public enum ProviderErrorMapper {
    public static func map(statusCode: Int) -> TranslationProviderError {
        switch statusCode {
        case 401, 403:
            .invalidCredentials
        case 429:
            .rateLimited
        default:
            .server(statusCode: statusCode)
        }
    }

    public static func map(_ error: Error) -> TranslationProviderError {
        if error is CancellationError {
            return .cancelled
        }
        guard let urlError = error as? URLError else {
            return .invalidResponse
        }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
            return .networkUnavailable
        case .timedOut:
            return .timedOut
        case .cancelled:
            return .cancelled
        default:
            return .invalidResponse
        }
    }
}
