import XCTest
import InstantTranslationCore
@testable import InstantTranslationInfrastructure

final class GoogleTranslationProviderTests: XCTestCase {
    func testBuildsOfficialV2RequestWithHeaderCredentialAndPlainTextBody() async throws {
        let transport = StubHTTPTransport(
            statusCode: 200,
            body: #"{"data":{"translations":[{"translatedText":"Just-in-time compilation"}]}}"#
        )
        let provider = GoogleTranslationProvider(transport: transport) { "google-secret" }
        let request = TranslationRequest(
            id: UUID(), text: "即时编译", inputSource: .manual,
            sourceLanguage: .simplifiedChinese, targetLanguage: .english,
            directionOrigin: .detected, promptPresetID: .technologyAndRnD
        )

        let result = try await provider.translate(request)
        let requests = await transport.requests
        let sent = try XCTUnwrap(requests.first)

        XCTAssertEqual(sent.url?.absoluteString, "https://translation.googleapis.com/language/translate/v2")
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.timeoutInterval, 15)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Goog-Api-Key"), "google-secret")
        XCTAssertFalse(sent.url?.absoluteString.contains("google-secret") ?? true)
        let body = try JSONDecoder().decode(
            RequestBody.self,
            from: try XCTUnwrap(sent.httpBody)
        )
        XCTAssertEqual(body.q, "即时编译")
        XCTAssertEqual(body.source, "zh-CN")
        XCTAssertEqual(body.target, "en")
        XCTAssertEqual(body.format, "text")
        XCTAssertEqual(result.primaryText, "Just-in-time compilation")
        XCTAssertNil(result.rationale)
    }

    func testMapsAuthenticationAndRateLimitFailures() async {
        let cases: [(status: Int, expected: TranslationProviderError)] = [
            (401, .invalidCredentials),
            (403, .invalidCredentials),
            (429, .rateLimited),
        ]

        for testCase in cases {
            let transport = StubHTTPTransport(statusCode: testCase.status, body: "{}")
            let provider = GoogleTranslationProvider(
                transport: transport,
                apiKey: { "key" }
            )

            do {
                _ = try await provider.translate(Self.request)
                XCTFail("Expected provider error")
            } catch {
                XCTAssertEqual(error as? TranslationProviderError, testCase.expected)
            }

            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testMapsOfflineAndTimeoutFailuresWithoutRetrying() async {
        let cases: [(code: URLError.Code, expected: TranslationProviderError)] = [
            (.notConnectedToInternet, .networkUnavailable),
            (.timedOut, .timedOut),
        ]

        for testCase in cases {
            let transport = StubHTTPTransport(error: URLError(testCase.code))
            let provider = GoogleTranslationProvider(transport: transport, apiKey: { "key" })

            do {
                _ = try await provider.translate(Self.request)
                XCTFail("Expected provider error")
            } catch {
                XCTAssertEqual(error as? TranslationProviderError, testCase.expected)
            }

            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testNilEmptyAndWhitespaceKeysAreUnconfiguredWithoutSending() async {
        let keys: [String?] = [nil, "", " \n\t"]

        for key in keys {
            let transport = StubHTTPTransport(
                statusCode: 200,
                body: #"{"data":{"translations":[{"translatedText":"编译器"}]}}"#
            )
            let provider = GoogleTranslationProvider(transport: transport, apiKey: { key })

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

    func testInvalidSuccessPayloadIsRejected() async {
        let provider = GoogleTranslationProvider(
            transport: StubHTTPTransport(statusCode: 200, body: #"{"data":{}}"#),
            apiKey: { "key" }
        )

        do {
            _ = try await provider.translate(Self.request)
            XCTFail("Expected invalid response")
        } catch {
            XCTAssertEqual(error as? TranslationProviderError, .invalidResponse)
        }
    }

    func testWhitespaceOnlyTranslationIsRejected() async {
        let provider = GoogleTranslationProvider(
            transport: StubHTTPTransport(
                statusCode: 200,
                body: #"{"data":{"translations":[{"translatedText":" \n\t "}]}}"#
            ),
            apiKey: { "key" }
        )

        do {
            _ = try await provider.translate(Self.request)
            XCTFail("Expected invalid response")
        } catch {
            XCTAssertEqual(error as? TranslationProviderError, .invalidResponse)
        }
    }

    func testTrimsTranslatedTextBeforeReturningIt() async throws {
        let provider = GoogleTranslationProvider(
            transport: StubHTTPTransport(
                statusCode: 200,
                body: #"{"data":{"translations":[{"translatedText":" \n编译器\t "}]}}"#
            ),
            apiKey: { "key" }
        )

        let result = try await provider.translate(Self.request)

        XCTAssertEqual(result.primaryText, "编译器")
        XCTAssertEqual(result.speakableText, "编译器")
    }

    private static let request = TranslationRequest(
        id: UUID(), text: "compiler", inputSource: .manual,
        sourceLanguage: .english, targetLanguage: .simplifiedChinese,
        directionOrigin: .detected, promptPresetID: .technologyAndRnD
    )
}

private struct RequestBody: Decodable {
    let q: String
    let source: String
    let target: String
    let format: String
}
