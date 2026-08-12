import Foundation
import InstantTranslationCore

public enum EndpointPolicy {
    public static func validatedAPIBaseURL(_ value: String) throws -> URL {
        guard var components = URLComponents(string: value),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else {
            throw TranslationProviderError.insecureEndpoint
        }

        // 只移除 URL 文本中真实的尾随斜杠，绝不解码路径，以保留 %2F 与 %2e%2e 的语义。
        while components.percentEncodedPath.count > 1 && components.percentEncodedPath.hasSuffix("/") {
            components.percentEncodedPath.removeLast()
        }
        guard let url = components.url else {
            throw TranslationProviderError.insecureEndpoint
        }
        try validatedRequestURL(url)
        return url
    }

    static func validatedRequestURL(_ url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              components.user == nil,
              components.password == nil
        else {
            throw TranslationProviderError.insecureEndpoint
        }

        let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let loopback = normalizedHost == "localhost" || normalizedHost == "127.0.0.1" || normalizedHost == "::1"
        // 远程 HTTP 会明文暴露原文和凭据；仅允许本机 loopback 的 HTTP 以支持本地推理服务。
        guard scheme == "https" || (scheme == "http" && loopback) else {
            throw TranslationProviderError.insecureEndpoint
        }
    }
}
