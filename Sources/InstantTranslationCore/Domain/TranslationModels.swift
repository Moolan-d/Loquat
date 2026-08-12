import Foundation

public struct InputSourceID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let manual = Self(rawValue: "manual")
    public static let clipboard = Self(rawValue: "clipboard")
    public static let selection = Self(rawValue: "selection")
    public static let ocr = Self(rawValue: "ocr")
}

public struct PromptPresetID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let general = Self(rawValue: "general")
    public static let technologyAndRnD = Self(rawValue: "technology-and-r-and-d")
}

public struct ProviderID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let google = Self(rawValue: "google-cloud-translation")
    public static let llm = Self(rawValue: "openai-compatible-llm")
}

public struct PronunciationScheme: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct Pronunciation: Hashable, Codable, Sendable {
    public let scheme: PronunciationScheme
    public let text: String
    public let language: LanguageID
    public let source: ProviderID

    public init(scheme: PronunciationScheme, text: String, language: LanguageID, source: ProviderID) {
        self.scheme = scheme
        self.text = text
        self.language = language
        self.source = source
    }
}

public enum DirectionOrigin: String, Codable, Equatable, Sendable {
    case detected
    case manual
}

public struct TranslationRequest: Hashable, Sendable {
    public let id: UUID
    public let text: String
    public let inputSource: InputSourceID
    public let sourceLanguage: LanguageID
    public let targetLanguage: LanguageID
    public let directionOrigin: DirectionOrigin
    public let promptPresetID: PromptPresetID

    public init(
        id: UUID,
        text: String,
        inputSource: InputSourceID,
        sourceLanguage: LanguageID,
        targetLanguage: LanguageID,
        directionOrigin: DirectionOrigin,
        promptPresetID: PromptPresetID
    ) {
        self.id = id
        self.text = text
        self.inputSource = inputSource
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.directionOrigin = directionOrigin
        self.promptPresetID = promptPresetID
    }
}

public struct TranslationResult: Hashable, Sendable {
    public let providerID: ProviderID
    public let requestID: UUID
    public let primaryText: String
    public let rationale: String?
    public let sourceLanguage: LanguageID
    public let targetLanguage: LanguageID
    public let pronunciations: [Pronunciation]
    public let speakableText: String?
    public let duration: Duration

    public init(
        providerID: ProviderID,
        requestID: UUID,
        primaryText: String,
        rationale: String?,
        sourceLanguage: LanguageID,
        targetLanguage: LanguageID,
        pronunciations: [Pronunciation],
        speakableText: String?,
        duration: Duration
    ) {
        self.providerID = providerID
        self.requestID = requestID
        self.primaryText = primaryText
        self.rationale = rationale
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.pronunciations = pronunciations
        self.speakableText = speakableText
        self.duration = duration
    }
}
