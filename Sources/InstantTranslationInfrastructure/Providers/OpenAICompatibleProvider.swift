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

public struct OpenAICompatibleProvider: TranslationProvider, ContextExpansionProvider {
    public let id = ProviderID.llm

    private let senseExpansion = SenseExpansionPolicy()
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
        let (content, duration) = try await responseContent(
            for: request,
            userPrompt: LLMUserPrompt.build(
                for: request,
                expandsSenses: senseExpansion.shouldExpand(request.text)
            )
        )
        let parsed = try LLMResponseParser.parse(content)

        return TranslationResult(
            providerID: id,
            requestID: request.id,
            primaryText: parsed.translation,
            rationale: parsed.rationale,
            senses: parsed.senses,
            phrases: parsed.phrases,
            sourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage,
            pronunciations: [],
            speakableText: parsed.translation,
            duration: duration
        )
    }

    /// 用户点「更多语境」才走到这里，且只走这一次。刻意不从 translate 里调用：
    /// 首译的成本要保持在一次请求，多数查询到此为止。
    public func expandContext(
        for request: TranslationRequest,
        excluding existingResult: TranslationResult
    ) async throws -> ContextExpansionResult {
        let (content, _) = try await responseContent(
            for: request,
            userPrompt: LLMContextPrompt.build(for: request, excluding: existingResult)
        )
        let parsed = try LLMResponseParser.parseContextExpansion(content)
        return ContextExpansionResult(requestID: request.id, senses: parsed.senses)
    }

    /// 两次请求共用的传输路径：凭据校验、endpoint 白名单、超时、错误映射、envelope 解析。
    /// 抄第二遍的话，安全策略就会有两处各自演化的版本。
    private func responseContent(
        for request: TranslationRequest,
        userPrompt: String
    ) async throws -> (content: String, duration: Duration) {
        guard let configuration = try await configuration(request.promptPresetID) else {
            throw TranslationProviderError.unconfigured
        }
        let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        // 模型留空时按 base URL 兜底。兜底在这里而不是在设置里落盘，两次请求
        // （首译与按需语境）也就自动共用同一个结论；兜不住的仍然落到 unconfigured。
        let requestedModel = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = requestedModel.isEmpty
            ? LLMDefaultModel.resolve(baseURL: configuration.baseURL) ?? ""
            : requestedModel
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
        return (content, start.duration(to: clock.now))
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
