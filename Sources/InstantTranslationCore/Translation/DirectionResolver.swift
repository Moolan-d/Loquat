public struct TranslationDirection: Equatable, Sendable {
    public let source: LanguageID
    public let target: LanguageID

    public init(source: LanguageID, target: LanguageID) {
        self.source = source
        self.target = target
    }
}

public struct DirectionResolver: Sendable {
    public init() {}

    public func resolve(_ text: String) -> TranslationDirection {
        HanScript.contains(text)
            ? .init(source: .simplifiedChinese, target: .english)
            : .init(source: .english, target: .simplifiedChinese)
    }
}
