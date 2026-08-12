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
        // 覆盖 CJK 统一表意文字及扩展 A、兼容表意文字，避免仅依赖常用汉字范围误判输入方向。
        let containsHan = text.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
        }

        return containsHan
            ? .init(source: .simplifiedChinese, target: .english)
            : .init(source: .english, target: .simplifiedChinese)
    }
}
