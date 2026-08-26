import InstantTranslationCore

/// 用户点「更多语境」后那一次请求的 user message。
/// 把首译已经给过的义项原样带上，模型才不会把同样的话再说一遍——
/// 这是第二次请求唯一的价值来源：说第一次刻意没说的东西。
public enum LLMContextPrompt {
    public static func build(
        for request: TranslationRequest,
        excluding result: TranslationResult
    ) -> String {
        let covered = result.senses
            .map { "- \($0.label): \($0.meaning)" }
            .joined(separator: "\n")
        return """
        Source language: \(request.sourceLanguage.rawValue)
        Target language: \(request.targetLanguage.rawValue)
        Text: \(request.text)
        Existing translation: \(result.primaryText)
        Already covered senses:
        \(covered.isEmpty ? "- none" : covered)

        Reply with one JSON object and nothing else. Add "senses": an array of at most 3 additional, genuinely useful contexts not already covered. Prefer current slang, internet, or subculture usage only when it is real and relevant. Each object has "label", "meaning", optional source-language "example", and optional target-language "exampleTranslation". Do not add "translation", "rationale", or "phrases". An empty array is valid when no additional context is worth showing.
        """
    }
}
