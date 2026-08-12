import Foundation
import InstantTranslationCore

public enum ProviderCardState: Equatable, Sendable {
    case idle
    case loading(requestID: UUID)
    case success(TranslationResult)
    case failure(requestID: UUID, TranslationProviderError)
}
