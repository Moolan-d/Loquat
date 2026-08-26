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

    func testRejectsUnclosedMarkdownFences() {
        let contents = [
            "```json\n{\"translation\":\"compiler\"",
            "```\ncompiler",
            "````\ncompiler\n```",
        ]

        assertInvalidResponses(contents)
    }

    func testRejectsJSONShapedResponsesThatDoNotMatchExpectedObject() {
        let contents = [
            "```json\n{\"translation\":\"compiler\"\n```",
            "```JSON\n{\"answer\":\"compiler\"}\n```",
            "```json\ncompiler\n```",
            "```json\n[\"compiler\"]\n```",
            #"{"answer":"compiler"}"#,
            #"{"translation":"compiler""#,
            #"["compiler"]"#,
            #"["compiler""#,
            #""compiler""#,
            "42",
            "-0.5e+2",
            "true",
            "false",
            "null",
        ]

        assertInvalidResponses(contents)
    }

    func testPlainTextBeginningWithUnmatchedQuoteStillUsesFirstLineFallback() throws {
        XCTAssertEqual(
            try LLMResponseParser.parse("\"compiler term\nAdditional prose"),
            .init(translation: "\"compiler term", rationale: nil)
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

        assertInvalidResponses(contents)
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
                content: LLMUserPrompt.build(for: Self.request, expandsSenses: true)
            ),
        ])
        XCTAssertEqual(result.providerID, .llm)
        XCTAssertEqual(result.requestID, Self.request.id)
        XCTAssertEqual(result.primaryText, "compiler")
        XCTAssertEqual(result.rationale, "Standard term.")
        XCTAssertEqual(result.speakableText, "compiler")
    }

    func testUserPromptCarriesTheJSONContractAndTheInputItself() {
        let prompt = LLMUserPrompt.build(for: Self.request, expandsSenses: false)

        XCTAssertTrue(prompt.contains("Source language: zh-Hans"))
        XCTAssertTrue(prompt.contains("Target language: en"))
        XCTAssertTrue(prompt.contains("Text: 编译器"))
        // 契约归代码：系统提示词是用户可改的，字段约定不能只写在那边。
        XCTAssertTrue(prompt.contains(#""translation""#))
        XCTAssertFalse(DefaultPrompts.general.contains(#""translation""#))
        XCTAssertFalse(DefaultPrompts.technologyAndRnD.contains(#""translation""#))
    }

    func testFirstLookupPromptStaysCompactAndSkipsNicheContexts() {
        let lookup = LLMUserPrompt.build(for: Self.request, expandsSenses: true)

        XCTAssertTrue(lookup.contains("at most 3"))
        XCTAssertTrue(lookup.contains("at most 1"))
        XCTAssertTrue(lookup.contains(#""exampleTranslation""#))
        XCTAssertTrue(lookup.contains("Do not repeat"))
        XCTAssertTrue(lookup.contains("up to 3 distinct target-language equivalents"))
        // 网络、亚文化义项移到了点击后的第二次请求，首译不该主动去要。
        XCTAssertFalse(lookup.contains("include slang or internet usage whenever"))
    }

    func testUserPromptOnlyAsksForSensesWhenTheInputLooksLikeALookup() {
        let lookup = LLMUserPrompt.build(for: Self.request, expandsSenses: true)
        let sentence = LLMUserPrompt.build(for: Self.request, expandsSenses: false)

        XCTAssertTrue(lookup.contains(#""senses""#))
        XCTAssertTrue(lookup.contains(#""phrases""#))
        // 翻译整句时义项无处可用，指令必须整段消失，而不是让模型自己判断要不要理会。
        XCTAssertFalse(sentence.contains(#""senses""#))
        XCTAssertFalse(sentence.contains(#""phrases""#))
        XCTAssertFalse(sentence.contains(#""exampleTranslation""#))
    }

    func testContextPromptCarriesWhatWasAlreadyCoveredAndAsksOnlyForSenses() {
        let existing = Self.makeResult(
            senses: [.init(label: "心理学", meaning: "自我意识", example: nil)]
        )

        let prompt = LLMContextPrompt.build(for: Self.request, excluding: existing)

        XCTAssertTrue(prompt.contains("Text: 编译器"))
        XCTAssertTrue(prompt.contains("Existing translation: 自我；自尊心；自负"))
        // 已覆盖的义项必须原样带上，否则第二次请求会把第一次的内容再说一遍。
        XCTAssertTrue(prompt.contains("- 心理学: 自我意识"))
        XCTAssertTrue(prompt.contains("additional"))
        XCTAssertTrue(prompt.contains(#""senses""#))
        // 搭配、主译文、rationale 首译已经给过了，这次要明说别再给一遍。
        XCTAssertTrue(
            prompt.contains(#"Do not add "translation", "rationale", or "phrases""#)
        )
    }

    func testContextPromptSaysNoneWhenTheFirstResponseCarriedNoSenses() {
        let prompt = LLMContextPrompt.build(for: Self.request, excluding: Self.makeResult())

        XCTAssertTrue(prompt.contains("- none"))
    }

    func testFirstResponseIsCompactedToThreeSensesAndOneCollocation() throws {
        let parsed = try LLMResponseParser.parse(
            #"{"translation":"自我；自尊心；自负","rationale":"核心义是人的自我意识。","senses":[{"label":"心理学","meaning":"自我意识"},{"label":"日常","meaning":"自尊心、面子","example":"His ego was bruised.","exampleTranslation":"他的自尊心受挫了。"},{"label":"贬义","meaning":"自负、以自我为中心"},{"label":"贬义","meaning":"自负、以自我为中心"}],"phrases":[{"phrase":"alter ego","meaning":"另一个自我"},{"phrase":"ego boost","meaning":"提升自信"}]}"#
        )

        // 上限在解析器一处收口；模型多给了就在这里截断，界面不再重复一遍限额。
        XCTAssertEqual(parsed.senses.count, 3)
        XCTAssertEqual(parsed.phrases, [.init(phrase: "alter ego", meaning: "另一个自我")])
        XCTAssertEqual(parsed.senses[1].example, "His ego was bruised.")
        XCTAssertEqual(parsed.senses[1].exampleTranslation, "他的自尊心受挫了。")
        XCTAssertNil(parsed.senses[0].example)
        XCTAssertNil(parsed.senses[0].exampleTranslation)
    }

    func testDuplicateSensesAreRemovedByMeaningRegardlessOfLabel() throws {
        let parsed = try LLMResponseParser.parse(
            #"{"translation":"自我","senses":[{"label":"日常","meaning":" 自尊心 "},{"label":"口语","meaning":"自尊心"},{"label":"心理学","meaning":"自我意识"},{"label":"贬义","meaning":""}]}"#
        )

        // 同一个释义换个标签再来一遍是模型的常见浪费；按释义去重，先到的留下。
        XCTAssertEqual(parsed.senses.map(\.label), ["日常", "心理学"])
        XCTAssertEqual(parsed.senses[0].meaning, "自尊心")
    }

    func testContextExpansionParsesSensesOnlyAndClampsToThree() throws {
        let parsed = try LLMResponseParser.parseContextExpansion(
            #"{"senses":[{"label":"网络","meaning":"自恋"},{"label":"游戏","meaning":"上头"},{"label":"嘻哈","meaning":"面子"},{"label":"多余","meaning":"第四条"}]}"#
        )

        XCTAssertEqual(parsed.senses.count, 3)
        XCTAssertEqual(parsed.senses.map(\.label), ["网络", "游戏", "嘻哈"])
    }

    func testEmptyContextExpansionSucceedsButMalformedOneFails() throws {
        // 「没有更多语境可说」是一个正常答案，不是错误。
        XCTAssertEqual(try LLMResponseParser.parseContextExpansion(#"{"senses":[]}"#).senses, [])

        for content in ["not json", "", #"{"translation":"自我"}"#] {
            XCTAssertThrowsError(try LLMResponseParser.parseContextExpansion(content)) { error in
                XCTAssertEqual(error as? TranslationProviderError, .invalidResponse)
            }
        }
    }

    func testDecorativeFieldsNeverCostTheTranslationThatWasAlreadyInHand() throws {
        // senses 整段类型不对、个别条目缺字段、phrases 是字符串——译文都得照常交付。
        let parsed = try LLMResponseParser.parse(
            #"{"translation":"牛肉","senses":"抱怨","phrases":"beef up"}"#
        )
        XCTAssertEqual(parsed.translation, "牛肉")
        XCTAssertEqual(parsed.senses, [])
        XCTAssertEqual(parsed.phrases, [])

        let partial = try LLMResponseParser.parse(
            #"{"translation":"牛肉","senses":[{"label":"俚语"},{"label":"基本义","meaning":"牛肉"}]}"#
        )
        // 坏掉的是一条，不是一整块：另一条仍旧呈现。
        XCTAssertEqual(partial.senses, [.init(label: "基本义", meaning: "牛肉", example: nil)])
    }

    func testContextExpansionIsASecondRequestThatFirstTranslationNeverTriggers() async throws {
        let transport = StubHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"choices":[{"message":{"content":"{\"translation\":\"自我\",\"senses\":[{\"label\":\"心理学\",\"meaning\":\"自我意识\"}],\"phrases\":[{\"phrase\":\"alter ego\",\"meaning\":\"另一个自我\"}]}"}}]}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"choices":[{"message":{"content":"{\"senses\":[{\"label\":\"网络\",\"meaning\":\"自恋\"}]}"}}]}"#
            ),
        ])
        let provider = Self.provider(transport: transport)

        let initial = try await provider.translate(Self.request)

        // 首译只发一次；网络义项要等用户开口才去要。
        var requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(initial.phrases.count, 1)

        let expansion = try await provider.expandContext(for: Self.request, excluding: initial)

        requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(expansion.requestID, Self.request.id)
        XCTAssertEqual(expansion.senses.map(\.label), ["网络"])
        let secondBody = String(
            data: try XCTUnwrap(requests[1].httpBody),
            encoding: .utf8
        ) ?? ""
        XCTAssertTrue(secondBody.contains("additional"))
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

    func testBlankModelFallsBackToTheOpenRouterFreeRouter() async throws {
        let transport = StubHTTPTransport(statusCode: 200, body: Self.successBody)
        let provider = OpenAICompatibleProvider(transport: transport) { _ in
            .init(
                baseURL: "https://openrouter.ai/api/v1",
                apiKey: "key",
                model: "  ",
                systemPrompt: DefaultPrompts.general
            )
        }

        _ = try await provider.translate(Self.request)

        let requests = await transport.requests
        let sent = try XCTUnwrap(requests.first)
        let body = try JSONDecoder().decode(LLMRequestBody.self, from: try XCTUnwrap(sent.httpBody))
        XCTAssertEqual(body.model, "openrouter/free")
    }

    func testExplicitModelIsNeverReplacedByTheFallback() async throws {
        let transport = StubHTTPTransport(statusCode: 200, body: Self.successBody)
        let provider = OpenAICompatibleProvider(transport: transport) { _ in
            .init(
                baseURL: "https://openrouter.ai/api/v1",
                apiKey: "key",
                model: "anthropic/claude-sonnet-4.5",
                systemPrompt: DefaultPrompts.general
            )
        }

        _ = try await provider.translate(Self.request)

        let requests = await transport.requests
        let sent = try XCTUnwrap(requests.first)
        let body = try JSONDecoder().decode(LLMRequestBody.self, from: try XCTUnwrap(sent.httpBody))
        XCTAssertEqual(body.model, "anthropic/claude-sonnet-4.5")
    }

    /// 按需语境和首译共用同一条兜底路径，否则「更多语境」会在留空模型时报 unconfigured。
    func testContextExpansionUsesTheSameFallbackModel() async throws {
        let transport = StubHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"choices":[{"message":{"content":"{\"senses\":[{\"label\":\"网络\",\"meaning\":\"自恋\"}]}"}}]}"#
            ),
        ])
        let provider = OpenAICompatibleProvider(transport: transport) { _ in
            .init(
                baseURL: "https://openrouter.ai/api/v1",
                apiKey: "key",
                model: "",
                systemPrompt: DefaultPrompts.general
            )
        }

        let expansion = try await provider.expandContext(
            for: Self.request,
            excluding: Self.makeResult()
        )

        XCTAssertEqual(expansion.senses.map(\.label), ["网络"])
        let requests = await transport.requests
        let sent = try XCTUnwrap(requests.first)
        let body = try JSONDecoder().decode(LLMRequestBody.self, from: try XCTUnwrap(sent.httpBody))
        XCTAssertEqual(body.model, "openrouter/free")
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

    private static func makeResult(senses: [WordSense] = []) -> TranslationResult {
        TranslationResult(
            providerID: .llm,
            requestID: request.id,
            primaryText: "自我；自尊心；自负",
            rationale: nil,
            senses: senses,
            phrases: [],
            sourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage,
            pronunciations: [],
            speakableText: "自我；自尊心；自负",
            duration: .zero
        )
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

    private func assertInvalidResponses(
        _ contents: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for content in contents {
            XCTAssertThrowsError(
                try LLMResponseParser.parse(content),
                file: file,
                line: line
            ) { error in
                XCTAssertEqual(
                    error as? TranslationProviderError,
                    .invalidResponse,
                    file: file,
                    line: line
                )
            }
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
