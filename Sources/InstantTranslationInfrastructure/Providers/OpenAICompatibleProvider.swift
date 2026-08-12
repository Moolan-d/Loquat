import Foundation
import InstantTranslationCore

public struct LLMProviderConfiguration: Sendable {
    public let baseURL: String
    public let apiKey: String
    public let model: String
    public let systemPrompt: String

    public init(baseURL: String, apiKey: String, model: String, systemPrompt: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.systemPrompt = systemPrompt
    }
}

public struct OpenAICompatibleProvider: TranslationProvider {
    public let id = ProviderID.llm

    private let transport: any HTTPTransport
    private let configuration: @Sendable (PromptPresetID) async throws -> LLMProviderConfiguration?

    public init(
        transport: any HTTPTransport,
        configuration: @escaping @Sendable (PromptPresetID) async throws -> LLMProviderConfiguration?
    ) {
        self.transport = transport
        self.configuration = configuration
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        guard let configuration = try await configuration(request.promptPresetID) else {
            throw TranslationProviderError.unconfigured
        }
        let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty,
              !model.isEmpty,
              !configuration.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw TranslationProviderError.unconfigured
        }

        // 先验证 API 根地址，再构造并附加 Authorization，确保密钥只发往已批准的同源 endpoint。
        let baseURL = try EndpointPolicy.validatedAPIBaseURL(configuration.baseURL)
        let url = baseURL.appending(path: "chat/completions")
        var urlRequest = URLRequest(url: url, timeoutInterval: 60)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let userPrompt = """
        Source language: \(request.sourceLanguage.rawValue)
        Target language: \(request.targetLanguage.rawValue)
        Text: \(request.text)
        """
        // OpenAI-compatible 服务差异较大；首版固定非流式响应，保持单次 envelope 解析与错误映射确定。
        urlRequest.httpBody = try JSONEncoder().encode(
            ChatRequest(
                model: model,
                messages: [
                    .init(role: "system", content: configuration.systemPrompt),
                    .init(role: "user", content: userPrompt),
                ],
                temperature: 0,
                stream: false
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

        let envelope: ChatEnvelope
        do {
            envelope = try JSONDecoder().decode(ChatEnvelope.self, from: response.data)
        } catch {
            throw TranslationProviderError.invalidResponse
        }
        guard let content = envelope.choices.first?.message.content else {
            throw TranslationProviderError.invalidResponse
        }
        let parsed = try LLMResponseParser.parse(content)

        return TranslationResult(
            providerID: id,
            requestID: request.id,
            primaryText: parsed.translation,
            rationale: parsed.rationale,
            sourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage,
            pronunciations: [],
            speakableText: parsed.translation,
            duration: start.duration(to: clock.now)
        )
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Int
    let stream: Bool
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

private struct ChatEnvelope: Decodable {
    let choices: [ChatChoice]
}

private struct ChatChoice: Decodable {
    let message: ChatResponseMessage
}

private struct ChatResponseMessage: Decodable {
    let content: String
}
