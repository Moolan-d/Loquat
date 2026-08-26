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

/// 一个词条的一层含义。label 是这层含义的出处——基本、俚语、网络用语、嘻哈文化……
/// 刻意不做成枚举：网络说法的分类本来就在长，写死一份 case 只会让新说法无处可归。
public struct WordSense: Hashable, Codable, Sendable {
    public let label: String
    public let meaning: String
    /// 例句用源语言，译文用目标语言，两者分开存：原文排斜体、译文不排，
    /// 合成一个字符串就再也分不开了。
    public let example: String?
    public let exampleTranslation: String?

    public init(
        label: String,
        meaning: String,
        example: String?,
        exampleTranslation: String? = nil
    ) {
        self.label = label
        self.meaning = meaning
        self.example = example
        self.exampleTranslation = exampleTranslation
    }
}

/// 用户点「更多语境」后那一次额外请求的产物。绑着 requestID，
/// 迟到的那份才认得出自己属于哪一轮，不会贴到新一次查询的结果上。
public struct ContextExpansionResult: Hashable, Sendable {
    public let requestID: UUID
    public let senses: [WordSense]

    public init(requestID: UUID, senses: [WordSense]) {
        self.requestID = requestID
        self.senses = senses
    }
}

/// 以查询词为核心的固定搭配或短语动词，例如 beef 之于 beef up。
public struct PhraseUsage: Hashable, Codable, Sendable {
    public let phrase: String
    public let meaning: String

    public init(phrase: String, meaning: String) {
        self.phrase = phrase
        self.meaning = meaning
    }
}

public struct TranslationResult: Hashable, Sendable {
    public let providerID: ProviderID
    public let requestID: UUID
    public let primaryText: String
    public let rationale: String?
    /// 义项与搭配只在「查词」时才有内容；翻译整句时两者都是空数组。
    public let senses: [WordSense]
    public let phrases: [PhraseUsage]
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
        senses: [WordSense] = [],
        phrases: [PhraseUsage] = [],
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
        self.senses = senses
        self.phrases = phrases
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.pronunciations = pronunciations
        self.speakableText = speakableText
        self.duration = duration
    }
}
