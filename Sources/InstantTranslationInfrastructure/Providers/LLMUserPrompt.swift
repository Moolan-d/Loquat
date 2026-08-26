import InstantTranslationCore

/// 每次首译请求的 user message。响应结构的契约在这里，也只在这里——
/// 系统提示词是用户可改的，把字段约定放在那边等于让用户随手就能改坏解析。
public enum LLMUserPrompt {
    public static func build(
        for request: TranslationRequest,
        expandsSenses: Bool
    ) -> String {
        var prompt = """
        Source language: \(request.sourceLanguage.rawValue)
        Target language: \(request.targetLanguage.rawValue)
        Text: \(request.text)

        Reply with one JSON object and nothing else. Fields: "translation" (string, required) is the translation of Text into the target language; "rationale" (string, optional) is one short target-language explanation of the core distinction that does not restate the translation.
        """

        // 查词才追加这段。翻译整句时义项无处可用，还会让响应变长、变慢。
        // 首译刻意只要常见义项：网络、嘻哈这类小众语境留给用户点击后的第二次请求，
        // 免得每查一个词都为多数人用不上的内容付出等待。
        if expandsSenses {
            prompt += """


            Text is a word or short expression. The "translation" is one line containing up to 3 distinct target-language equivalents when multiple equivalents are genuinely useful; separate them with natural target-language punctuation and do not add definitions. Add "senses": at most 3 common, meaningfully distinct senses ordered by usefulness. Do not repeat the translation, rationale, or another sense. Exclude niche internet, fandom, music, and subculture meanings from this first response. Each sense has "label", "meaning", optional source-language "example", and optional target-language "exampleTranslation". Add "phrases": at most 1 object containing the single most useful fixed collocation with "phrase" and "meaning". Omit empty sections.
            """
        }

        return prompt
    }
}
