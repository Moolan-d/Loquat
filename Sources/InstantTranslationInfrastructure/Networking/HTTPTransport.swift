import Foundation
import InstantTranslationCore

public struct HTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int

    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public actor URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession
    private let redirectDelegate: EndpointPolicyRedirectDelegate

    public init() {
        let redirectDelegate = EndpointPolicyRedirectDelegate()
        self.redirectDelegate = redirectDelegate
        session = URLSession(
            configuration: Self.makeConfiguration(),
            delegate: redirectDelegate,
            delegateQueue: nil
        )
    }

    public static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        // 翻译请求可能携带原文和访问令牌；禁用磁盘缓存、Cookie 与凭据存储，避免它们跨会话落盘。
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        return configuration
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        guard let url = request.url else {
            throw TranslationProviderError.insecureEndpoint
        }
        try EndpointPolicy.validatedRequestURL(url)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return HTTPResponse(data: data, statusCode: response.statusCode)
    }

    static func shouldFollowRedirect(to request: URLRequest) -> Bool {
        guard let url = request.url else {
            return false
        }
        return (try? EndpointPolicy.validatedRequestURL(url)) != nil
    }

    static func redirectRequest(from sourceURL: URL?, to request: URLRequest) -> URLRequest? {
        guard shouldFollowRedirect(to: request),
              let sourceURL,
              let targetURL = request.url
        else {
            return nil
        }
        guard RequestOrigin(url: sourceURL) == RequestOrigin(url: targetURL)
                || !containsSensitiveHeaders(request)
        else {
            return nil
        }
        return request
    }

    private static func containsSensitiveHeaders(_ request: URLRequest) -> Bool {
        let fields = [
            "Authorization",
            "Proxy-Authorization",
            "Cookie",
            "X-Goog-Api-Key",
            "X-Api-Key",
            "Api-Key",
        ]
        return fields.contains { request.value(forHTTPHeaderField: $0) != nil }
    }
}

private final class EndpointPolicyRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // Foundation 是否保留认证 header 不能作为安全边界；scheme、host 或 port 改变且仍携密时直接拒绝。
        completionHandler(URLSessionHTTPTransport.redirectRequest(from: response.url, to: request))
    }
}

private struct RequestOrigin: Equatable {
    let scheme: String
    let host: String
    let port: Int

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased()
        else {
            return nil
        }
        let defaultPort: Int
        switch scheme {
        case "https":
            defaultPort = 443
        case "http":
            defaultPort = 80
        default:
            return nil
        }
        self.scheme = scheme
        self.host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        port = components.port ?? defaultPort
    }
}
