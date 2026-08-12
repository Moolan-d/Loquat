public enum ClipboardDecision: Equatable, Sendable {
    case ignore
    case translate(SourceText)
    case requireConfirmation(SourceText)

    public var shouldSubmit: Bool {
        if case .translate = self {
            return true
        }
        return false
    }
}

public struct ClipboardTextPolicy: Sendable {
    public let automaticCharacterLimit: Int

    public init(automaticCharacterLimit: Int = 500) {
        self.automaticCharacterLimit = automaticCharacterLimit
    }

    public func evaluate(_ rawValue: String?) -> ClipboardDecision {
        guard let rawValue,
              let text = SourceText(rawValue: rawValue, sourceID: .clipboard)
        else {
            return .ignore
        }

        return text.value.count <= automaticCharacterLimit
            ? .translate(text)
            : .requireConfirmation(text)
    }
}
