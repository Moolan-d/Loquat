import XCTest
@testable import InstantTranslationCore

final class TranslationCoordinatorTests: XCTestCase {
    func testPublishesFastProviderWithoutWaitingForSlowProvider() async {
        let fast = DelayedProvider(id: .google, delay: .milliseconds(5), text: "fast")
        let slow = DelayedProvider(id: .llm, delay: .milliseconds(100), text: "slow")
        let coordinator = TranslationCoordinator(providers: [fast, slow])
        var iterator = coordinator.events(for: Self.request).makeAsyncIterator()

        guard case .success(let result)? = await iterator.next() else {
            return XCTFail("Expected the fast provider to succeed first")
        }

        XCTAssertEqual(result.providerID, .google)
        XCTAssertEqual(result.primaryText, "fast")
    }

    func testLLMCanPublishBeforeGoogle() async {
        let google = DelayedProvider(id: .google, delay: .milliseconds(100), text: "slow")
        let llm = DelayedProvider(id: .llm, delay: .milliseconds(5), text: "fast")
        var iterator = TranslationCoordinator(providers: [google, llm])
            .events(for: Self.request)
            .makeAsyncIterator()

        guard case .success(let result)? = await iterator.next() else {
            return XCTFail("Expected the fast provider to succeed first")
        }

        XCTAssertEqual(result.providerID, .llm)
    }

    func testOneFailureDoesNotSuppressOtherSuccess() async {
        let success = DelayedProvider(id: .google, delay: .milliseconds(5), text: "ok")
        let failure = FailingProvider(id: .llm, error: .rateLimited)
        var sawSuccess = false
        var sawFailure = false

        for await event in TranslationCoordinator(providers: [success, failure])
            .events(for: Self.request)
        {
            switch event {
            case .success(let result):
                sawSuccess = result.providerID == .google
            case .failure(let providerID, _, let error):
                sawFailure = providerID == .llm && error == .rateLimited
            }
        }

        XCTAssertTrue(sawSuccess)
        XCTAssertTrue(sawFailure)
    }

    private static let request = TranslationRequest(
        id: UUID(),
        text: "term",
        inputSource: .manual,
        sourceLanguage: .english,
        targetLanguage: .simplifiedChinese,
        directionOrigin: .detected,
        promptPresetID: .technologyAndRnD
    )
}

private struct DelayedProvider: TranslationProvider {
    let id: ProviderID
    let delay: Duration
    let text: String

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        try await Task.sleep(for: delay)
        return TranslationResult(
            providerID: id,
            requestID: request.id,
            primaryText: text,
            rationale: nil,
            sourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage,
            pronunciations: [],
            speakableText: text,
            duration: delay
        )
    }
}

private struct FailingProvider: TranslationProvider {
    let id: ProviderID
    let error: TranslationProviderError

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        throw error
    }
}
