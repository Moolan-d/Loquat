import Foundation
import InstantTranslationCore

public struct GoogleTranslationProvider: TranslationProvider {
    public let id = ProviderID.google

    private let transport: any HTTPTransport
    private let apiKey: @Sendable () async throws -> String?

    public init(
        transport: any HTTPTransport,
        apiKey: @escaping @Sendable () async throws -> String?
    ) {
        self.transport = transport
        self.apiKey = apiKey
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        guard let key = try await apiKey(), !key.isEmpty else {
            throw TranslationProviderError.unconfigured
        }

        let url = URL(string: "https://translation.googleapis.com/language/translate/v2")!
        // 固定 15 秒避免翻译请求无限期占用资源；请求本身由无持久化的 HTTPTransport 发送。
        var urlRequest = URLRequest(url: url, timeoutInterval: 15)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        // API key 必须放入 header，避免被 URL、代理日志或诊断记录意外暴露。
        urlRequest.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        urlRequest.httpBody = try JSONEncoder().encode(
            GoogleRequestBody(
                q: request.text,
                source: request.sourceLanguage.googleCode,
                target: request.targetLanguage.googleCode,
                format: "text"
            )
        )

        let clock = ContinuousClock()
        let start = clock.now
        let response: HTTPResponse
        do {
            response = try await transport.send(urlRequest)
        } catch {
            throw ProviderErrorMapper.map(error)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ProviderErrorMapper.map(statusCode: response.statusCode)
        }

        let envelope: GoogleResponseEnvelope
        do {
            envelope = try JSONDecoder().decode(GoogleResponseEnvelope.self, from: response.data)
        } catch {
            throw TranslationProviderError.invalidResponse
        }
        guard let translatedText = envelope.data.translations.first?.translatedText,
              !translatedText.isEmpty
        else {
            throw TranslationProviderError.invalidResponse
        }

        return TranslationResult(
            providerID: id,
            requestID: request.id,
            primaryText: translatedText,
            rationale: nil,
            sourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage,
            pronunciations: [],
            speakableText: translatedText,
            duration: start.duration(to: clock.now)
        )
    }
}

private struct GoogleRequestBody: Encodable {
    let q: String
    let source: String
    let target: String
    let format: String
}

private struct GoogleResponseEnvelope: Decodable {
    let data: GoogleResponseData
}

private struct GoogleResponseData: Decodable {
    let translations: [GoogleResponseTranslation]
}

private struct GoogleResponseTranslation: Decodable {
    let translatedText: String
}
