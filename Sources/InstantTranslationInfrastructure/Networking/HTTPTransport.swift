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
}

private final class EndpointPolicyRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // 重定向可能把 HTTPS 请求降级到 HTTP；每次跳转均重新执行与初始请求相同的安全策略。
        completionHandler(URLSessionHTTPTransport.shouldFollowRedirect(to: request) ? request : nil)
    }
}
