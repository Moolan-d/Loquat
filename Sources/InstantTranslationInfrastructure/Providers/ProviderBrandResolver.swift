import Foundation

public enum ProviderBrand: String, Equatable, Sendable {
    case googleTranslate
    case openAI
    case deepSeek
    case openRouter
    case genericAI
}

public enum ProviderBrandResolver {
    public static func resolve(baseURL: String) -> ProviderBrand {
        guard let host = URLComponents(string: baseURL)?.host?.lowercased() else {
            return .genericAI
        }

        if host == "api.openai.com" || host.hasSuffix(".openai.com") {
            return .openAI
        }
        if host == "api.deepseek.com" || host.hasSuffix(".deepseek.com") {
            return .deepSeek
        }
        if host == "openrouter.ai" || host.hasSuffix(".openrouter.ai") {
            return .openRouter
        }
        return .genericAI
    }
}
