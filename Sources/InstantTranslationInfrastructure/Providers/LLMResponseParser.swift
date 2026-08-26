import Foundation
import InstantTranslationCore

public struct ParsedLLMResponse: Equatable, Sendable {
    public let translation: String
    public let rationale: String?
    public let senses: [WordSense]
    public let phrases: [PhraseUsage]

    public init(
        translation: String,
        rationale: String?,
        senses: [WordSense] = [],
        phrases: [PhraseUsage] = []
    ) {
        self.translation = translation
        self.rationale = rationale
        self.senses = senses
        self.phrases = phrases
    }
}

/// 按需语境那一次请求的产物：只有义项，没有主译文、rationale 和搭配。
public struct ParsedContextExpansion: Equatable, Sendable {
    public let senses: [WordSense]

    public init(senses: [WordSense]) {
        self.senses = senses
    }
}

public enum LLMResponseParser {
    /// 义项与搭配的条数上限收在解析器一处。模型多给了就在这里截断，
    /// 界面只管画拿到的东西——限额写在两个地方，迟早只改其中一处。
    static let maximumSenseCount = 3
    static let maximumPhraseCount = 1

    public static func parse(_ content: String) throws -> ParsedLLMResponse {
        let (unfenced, requiresStructuredJSON) = try unfence(content)

        // 响应按结构化 JSON、Markdown 围栏内 JSON、首个可用纯文本行的固定顺序降级。
        if let data = unfenced.data(using: .utf8),
           let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
            let translation = value.translation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translation.isEmpty else {
                throw TranslationProviderError.invalidResponse
            }
            let rationale = value.rationale?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ParsedLLMResponse(
                translation: translation,
                rationale: rationale.flatMap { $0.isEmpty ? nil : $0 },
                senses: compact(value.senses),
                phrases: compact(value.phrases)
            )
        }

        if requiresStructuredJSON
            || isValidJSONDocument(unfenced)
            || unfenced.first == "{"
            || unfenced.first == "["
        {
            throw TranslationProviderError.invalidResponse
        }

        guard let firstLine = unfenced.split(separator: "\n")
            .map(String.init)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty })
        else {
            throw TranslationProviderError.invalidResponse
        }
        return ParsedLLMResponse(translation: firstLine, rationale: nil)
    }

    /// 剥掉 Markdown 围栏，并报告开栏是否显式标了 json——标了就不允许再降级到纯文本。
    private static func unfence(
        _ content: String
    ) throws -> (content: String, requiresStructuredJSON: Bool) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else {
            return (trimmed, false)
        }
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        let openingLine = lines.first ?? ""
        let openingFenceLength = openingLine.prefix { $0 == "`" }.count
        let fenceInfoText = openingLine.dropFirst(openingFenceLength)
        let closingLine = lines.last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let closingFenceLength = closingLine.prefix { $0 == "`" }.count
        guard lines.count >= 2,
              openingFenceLength >= 3,
              !fenceInfoText.contains("`"),
              closingFenceLength >= openingFenceLength,
              closingFenceLength == closingLine.count
        else {
            throw TranslationProviderError.invalidResponse
        }
        let fenceInfo = fenceInfoText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .first?
            .lowercased()
        return (
            lines.dropFirst().dropLast().joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            fenceInfo == "json"
        )
    }

    /// 按需语境的响应只认结构化 JSON：这次请求本来就是代码发起、代码消费的，
    /// 没有「模型回了一行纯文本也凑合用」的余地。
    public static func parseContextExpansion(_ content: String) throws -> ParsedContextExpansion {
        let unfenced = try unfence(content).content
        guard let data = unfenced.data(using: .utf8),
              let value = try? JSONDecoder().decode(ContextJSONValue.self, from: data)
        else {
            throw TranslationProviderError.invalidResponse
        }
        return ParsedContextExpansion(senses: compact(value.senses))
    }

    /// 保序、去空白、丢掉必填字段为空的条目，再按归一化后的内容去重，最后截断。
    private static func compact(_ senses: [WordSense]) -> [WordSense] {
        var seen = Set<String>()
        var kept: [WordSense] = []
        for sense in senses {
            let label = sense.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let meaning = sense.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, !meaning.isEmpty else { continue }
            // 按释义去重而不是按标签：同一个意思换个标签再来一遍是模型的常见浪费。
            guard seen.insert(meaning.lowercased()).inserted else { continue }
            kept.append(
                WordSense(
                    label: label,
                    meaning: meaning,
                    example: nonBlank(sense.example),
                    exampleTranslation: nonBlank(sense.exampleTranslation)
                )
            )
            if kept.count == maximumSenseCount { break }
        }
        return kept
    }

    private static func compact(_ phrases: [PhraseUsage]) -> [PhraseUsage] {
        var seen = Set<String>()
        var kept: [PhraseUsage] = []
        for usage in phrases {
            let phrase = usage.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            let meaning = usage.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty, !meaning.isEmpty else { continue }
            guard seen.insert(phrase.lowercased()).inserted else { continue }
            kept.append(PhraseUsage(phrase: phrase, meaning: meaning))
            if kept.count == maximumPhraseCount { break }
        }
        return kept
    }

    private static func nonBlank(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    private static func isValidJSONDocument(_ content: String) -> Bool {
        guard let data = content.data(using: .utf8) else {
            return false
        }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }
}

/// 只有 translation 能让整条响应作废。义项与搭配是锦上添花，
/// 它们缺失、类型不对、或某一条结构不全，都只该少显示一块，
/// 绝不该把已经拿到手的译文一起丢掉——那是用户唯一真正要的东西。
///
/// 直接解码成领域类型而不另设 DTO：字段约定就写在隔壁的 LLMUserPrompt 里，
/// 两者本来就得一起改，中间再插一层映射只是把同一份结构抄第二遍。
private struct JSONValue: Decodable {
    let translation: String
    let rationale: String?
    let senses: [WordSense]
    let phrases: [PhraseUsage]

    private enum CodingKeys: String, CodingKey {
        case translation, rationale, senses, phrases
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        translation = try container.decode(String.self, forKey: .translation)
        rationale = (try? container.decodeIfPresent(String.self, forKey: .rationale)) ?? nil
        senses = Self.tolerantList(WordSense.self, from: container, forKey: .senses)
        phrases = Self.tolerantList(PhraseUsage.self, from: container, forKey: .phrases)
    }

    private static func tolerantList<T: Decodable>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> [T] {
        let wrapped = (try? container.decodeIfPresent([Tolerant<T>].self, forKey: key)) ?? nil
        return wrapped?.compactMap(\.value) ?? []
    }
}

/// 解码时永不抛错的元素包装：单个条目坏掉就退化成 nil，
/// 剩下的条目照常呈现，而不是让整个数组陪葬。
private struct ContextJSONValue: Decodable {
    let senses: [WordSense]

    private enum CodingKeys: String, CodingKey {
        case senses
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // senses 键必须在。缺了说明模型答的根本不是这次请求要的东西。
        let wrapped = try container.decode([Tolerant<WordSense>].self, forKey: .senses)
        senses = wrapped.compactMap(\.value)
    }
}

private struct Tolerant<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: any Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}
