import Foundation

public struct LanguageID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let simplifiedChinese = Self(rawValue: "zh-Hans")
    public static let english = Self(rawValue: "en")

    public var googleCode: String {
        self == .simplifiedChinese ? "zh-CN" : rawValue
    }
}

public struct LanguageDescriptor: Hashable, Sendable {
    public let id: LanguageID
    public let displayName: String

    public init(id: LanguageID, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public struct LanguageCatalog: Sendable {
    public let languages: [LanguageDescriptor]

    public init(languages: [LanguageDescriptor]) {
        self.languages = languages
    }

    public static let initial = Self(languages: [
        .init(id: .simplifiedChinese, displayName: "中文"),
        .init(id: .english, displayName: "English"),
    ])
}
