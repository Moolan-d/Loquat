import Foundation
import InstantTranslationCore

public struct ParsedLLMResponse: Equatable, Sendable {
    public let translation: String
    public let rationale: String?

    public init(translation: String, rationale: String?) {
        self.translation = translation
        self.rationale = rationale
    }
}

public enum LLMResponseParser {
    public static func parse(_ content: String) throws -> ParsedLLMResponse {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let unfenced: String
        let requiresStructuredJSON: Bool
        if trimmed.hasPrefix("```") {
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
            requiresStructuredJSON = fenceInfo == "json"
            unfenced = lines.dropFirst().dropLast().joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            unfenced = trimmed
            requiresStructuredJSON = false
        }

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
                rationale: rationale.flatMap { $0.isEmpty ? nil : $0 }
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

    private static func isValidJSONDocument(_ content: String) -> Bool {
        guard let data = content.data(using: .utf8) else {
            return false
        }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }
}

private struct JSONValue: Decodable {
    let translation: String
    let rationale: String?
}
