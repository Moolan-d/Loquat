import XCTest
import InstantTranslationCore
@testable import InstantTranslationInfrastructure

final class OpenAICompatibleProviderTests: XCTestCase {
    func testParsesStructuredJSONResponse() throws {
        XCTAssertEqual(
            try LLMResponseParser.parse(
                #"{"translation":" compiler ","rationale":" Standard term. "}"#
            ),
            .init(translation: "compiler", rationale: "Standard term.")
        )
    }

    func testParsesJSONInsideMarkdownFence() throws {
        XCTAssertEqual(
            try LLMResponseParser.parse(
                "```json\n{\"translation\":\"compiler\",\"rationale\":\"Standard term.\"}\n```"
            ),
            .init(translation: "compiler", rationale: "Standard term.")
        )
    }

    func testDegradesPlainTextToFirstNonemptyLine() throws {
        XCTAssertEqual(
            try LLMResponseParser.parse(" \n compiler \nAdditional prose"),
            .init(translation: "compiler", rationale: nil)
        )
    }

    func testTreatsMissingOrBlankStructuredRationaleAsAbsent() throws {
        let contents = [
            #"{"translation":"compiler"}"#,
            #"{"translation":"compiler","rationale":" \n\t "}"#,
        ]

        for content in contents {
            XCTAssertEqual(
                try LLMResponseParser.parse(content),
                .init(translation: "compiler", rationale: nil)
            )
        }
    }

    func testRejectsResponsesWithoutUsableTranslationText() {
        let contents = [
            " \n\t ",
            #"{"translation":" \n\t ","rationale":"No translation."}"#,
            #"{"translation":"compiler""#,
        ]

        for content in contents {
            XCTAssertThrowsError(try LLMResponseParser.parse(content)) { error in
                XCTAssertEqual(error as? TranslationProviderError, .invalidResponse)
            }
        }
    }

    func testBuildsNonStreamingChatCompletionsRequestForSelectedPromptPreset() async throws {
        let transport = StubHTTPTransport(
            statusCode: 200,
            body: #"{"choices":[{"message":{"role":"assistant","content":"{\"translation\":\"compiler\",\"rationale\":\"Standard term.\"}"}}]}"#
        )
        let recorder = PromptPresetRecorder()
        let configuration = LLMProviderConfiguration(
            baseURL: "https://api.openai.com/v1/",
            apiKey: "llm-secret",
            model: "gpt-5-mini",
            systemPrompt: DefaultPrompts.technologyAndRnD
        )
        let provider = OpenAICompatibleProvider(transport: transport) { presetID in
            await recorder.record(presetID)
            return configuration
        }

        let result = try await provider.translate(Self.request)

        let selectedPresetIDs = await recorder.values
        XCTAssertEqual(selectedPresetIDs, [.technologyAndRnD])
        let requests = await transport.requests
        let sent = try XCTUnwrap(requests.first)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(sent.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.timeoutInterval, 60)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer llm-secret")
        XCTAssertFalse(sent.url?.absoluteString.contains("llm-secret") ?? true)

        let body = try JSONDecoder().decode(LLMRequestBody.self, from: try XCTUnwrap(sent.httpBody))
        XCTAssertEqual(body.model, "gpt-5-mini")
        XCTAssertEqual(body.temperature, 0)
        XCTAssertFalse(body.stream)
        XCTAssertEqual(body.messages, [
            .init(role: "system", content: DefaultPrompts.technologyAndRnD),
            .init(
                role: "user",
                content: "Source language: zh-Hans\nTarget language: en\nText: 编译器"
            ),
        ])
        XCTAssertEqual(result.providerID, .llm)
        XCTAssertEqual(result.requestID, Self.request.id)
        XCTAssertEqual(result.primaryText, "compiler")
        XCTAssertEqual(result.rationale, "Standard term.")
        XCTAssertEqual(result.speakableText, "compiler")
    }

    func testMissingOrBlankRequiredConfigurationIsUnconfiguredWithoutSending() async {
        let configurations: [LLMProviderConfiguration?] = [
            nil,
            .init(
                baseURL: "https://api.openai.com/v1",
                apiKey: " \n",
                model: "model",
                systemPrompt: DefaultPrompts.general
            ),
            .init(
                baseURL: "https://api.openai.com/v1",
                apiKey: "key",
                model: "\t",
                systemPrompt: DefaultPrompts.general
            ),
            .init(
                baseURL: "https://api.openai.com/v1",
                apiKey: "key",
                model: "model",
                systemPrompt: " \n"
            ),
        ]

        for configuration in configurations {
            let transport = StubHTTPTransport(statusCode: 200, body: Self.successBody)
            let provider = OpenAICompatibleProvider(transport: transport) { _ in configuration }

            do {
                _ = try await provider.translate(Self.request)
                XCTFail("Expected unconfigured")
            } catch {
                XCTAssertEqual(error as? TranslationProviderError, .unconfigured)
            }

            let requests = await transport.requests
            XCTAssertTrue(requests.isEmpty)
        }
    }

    func testRejectsRemoteHTTPBeforeSendingCredentialsAndAllowsLoopbackHTTP() async throws {
        let remoteTransport = StubHTTPTransport(statusCode: 200, body: Self.successBody)
        let remoteProvider = OpenAICompatibleProvider(transport: remoteTransport) { _ in
            .init(
                baseURL: "http://api.example.com/v1",
                apiKey: "secret",
                model: "model",
                systemPrompt: DefaultPrompts.general
            )
        }

        do {
            _ = try await remoteProvider.translate(Self.request)
            XCTFail("Expected insecure endpoint")
        } catch {
            XCTAssertEqual(error as? TranslationProviderError, .insecureEndpoint)
        }
        let remoteRequests = await remoteTransport.requests
        XCTAssertTrue(remoteRequests.isEmpty)

        let loopbackTransport = StubHTTPTransport(statusCode: 200, body: Self.successBody)
        let loopbackProvider = OpenAICompatibleProvider(transport: loopbackTransport) { _ in
            .init(
                baseURL: "http://127.0.0.1:11434/v1",
                apiKey: "local-secret",
                model: "model",
                systemPrompt: DefaultPrompts.general
            )
        }

        _ = try await loopbackProvider.translate(Self.request)

        let loopbackRequests = await loopbackTransport.requests
        let sent = try XCTUnwrap(loopbackRequests.first)
        XCTAssertEqual(sent.url?.absoluteString, "http://127.0.0.1:11434/v1/chat/completions")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer local-secret")
    }

    func testMapsAuthenticationAndRateLimitFailuresWithoutRetrying() async {
        let cases: [(statusCode: Int, error: TranslationProviderError)] = [
            (401, .invalidCredentials),
            (403, .invalidCredentials),
            (429, .rateLimited),
        ]

        for testCase in cases {
            let transport = StubHTTPTransport(statusCode: testCase.statusCode, body: "{}")
            let provider = Self.provider(transport: transport)

            do {
                _ = try await provider.translate(Self.request)
                XCTFail("Expected mapped provider error")
            } catch {
                XCTAssertEqual(error as? TranslationProviderError, testCase.error)
            }

            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testMapsOfflineAndTimeoutFailuresWithoutRetrying() async {
        let cases: [(code: URLError.Code, error: TranslationProviderError)] = [
            (.notConnectedToInternet, .networkUnavailable),
            (.timedOut, .timedOut),
        ]

        for testCase in cases {
            let transport = StubHTTPTransport(error: URLError(testCase.code))
            let provider = Self.provider(transport: transport)

            do {
                _ = try await provider.translate(Self.request)
                XCTFail("Expected mapped transport error")
            } catch {
                XCTAssertEqual(error as? TranslationProviderError, testCase.error)
            }

            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testRejectsInvalidChatEnvelopesAndWhitespaceContent() async {
        let bodies = [
            "not json",
            #"{"choices":[]}"#,
            #"{"choices":[{"message":{"role":"assistant","content":" \n\t "}}]}"#,
        ]

        for body in bodies {
            let transport = StubHTTPTransport(statusCode: 200, body: body)
            let provider = Self.provider(transport: transport)

            do {
                _ = try await provider.translate(Self.request)
                XCTFail("Expected invalid response")
            } catch {
                XCTAssertEqual(error as? TranslationProviderError, .invalidResponse)
            }
        }
    }

    func testAcceptsCompatibleEnvelopeWithoutResponseRole() async throws {
        let transport = StubHTTPTransport(
            statusCode: 200,
            body: #"{"choices":[{"message":{"content":"compiler"}}]}"#
        )
        let provider = Self.provider(transport: transport)

        let result = try await provider.translate(Self.request)

        XCTAssertEqual(result.primaryText, "compiler")
        XCTAssertNil(result.rationale)
    }

    private static let request = TranslationRequest(
        id: UUID(uuidString: "A04AB1B2-7C18-47D2-9554-62317D0EFCC5")!,
        text: "编译器",
        inputSource: .manual,
        sourceLanguage: .simplifiedChinese,
        targetLanguage: .english,
        directionOrigin: .detected,
        promptPresetID: .technologyAndRnD
    )

    private static let successBody = #"{"choices":[{"message":{"role":"assistant","content":"compiler"}}]}"#

    private static func provider(transport: any HTTPTransport) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(transport: transport) { _ in
            .init(
                baseURL: "https://api.openai.com/v1",
                apiKey: "key",
                model: "model",
                systemPrompt: DefaultPrompts.general
            )
        }
    }
}

private actor PromptPresetRecorder {
    private(set) var values: [PromptPresetID] = []

    func record(_ value: PromptPresetID) {
        values.append(value)
    }
}

private struct LLMRequestBody: Decodable {
    let model: String
    let messages: [LLMRequestMessage]
    let temperature: Int
    let stream: Bool
}

private struct LLMRequestMessage: Decodable, Equatable {
    let role: String
    let content: String
}
