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

    func testCoordinatorRunsLLMContextExpansionWithoutResubmittingTranslation() async throws {
        let provider = ExpandableProvider(id: .llm)
        let coordinator = TranslationCoordinator(providers: [provider])
        let existing = Self.makeResult(providerID: .llm, requestID: Self.request.id)

        let outcome = await coordinator.expandContext(for: Self.request, excluding: existing)

        let expansion = try outcome.get()
        XCTAssertEqual(expansion.requestID, Self.request.id)
        // 补充语境是独立一次请求，绝不能顺手把首译也重发一遍。
        let translateCallCount = await provider.probe.translateCallCount
        let expandCallCount = await provider.probe.expandCallCount
        XCTAssertEqual(translateCallCount, 0)
        XCTAssertEqual(expandCallCount, 1)
    }

    func testContextExpansionIsUnconfiguredWhenTheLLMCannotExpand() async {
        // Google 不具备这个能力，注册在 .llm 上的普通 provider 也一样：
        // 两种情况都该安静地报 unconfigured，而不是让界面挂在加载态。
        let plain = DelayedProvider(id: .llm, delay: .zero, text: "ok")
        let existing = Self.makeResult(providerID: .llm, requestID: Self.request.id)

        for providers in [[plain], []] as [[any TranslationProvider]] {
            let outcome = await TranslationCoordinator(providers: providers)
                .expandContext(for: Self.request, excluding: existing)
            XCTAssertEqual(outcome, .failure(.unconfigured))
        }
    }

    func testContextExpansionMapsProviderErrors() async {
        let coordinator = TranslationCoordinator(
            providers: [ExpandableProvider(id: .llm, error: .rateLimited)]
        )
        let existing = Self.makeResult(providerID: .llm, requestID: Self.request.id)

        let outcome = await coordinator.expandContext(for: Self.request, excluding: existing)

        XCTAssertEqual(outcome, .failure(.rateLimited))
    }

    static func makeResult(
        providerID: ProviderID,
        requestID: UUID
    ) -> TranslationResult {
        TranslationResult(
            providerID: providerID,
            requestID: requestID,
            primaryText: "自我",
            rationale: nil,
            sourceLanguage: .english,
            targetLanguage: .simplifiedChinese,
            pronunciations: [],
            speakableText: "自我",
            duration: .zero
        )
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

actor ExpansionProbe {
    private(set) var translateCallCount = 0
    private(set) var expandCallCount = 0

    func recordTranslate() { translateCallCount += 1 }
    func recordExpand() { expandCallCount += 1 }
}

private struct ExpandableProvider: TranslationProvider, ContextExpansionProvider {
    let id: ProviderID
    let probe = ExpansionProbe()
    var error: TranslationProviderError?

    init(id: ProviderID, error: TranslationProviderError? = nil) {
        self.id = id
        self.error = error
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        await probe.recordTranslate()
        return TranslationCoordinatorTests.makeResult(providerID: id, requestID: request.id)
    }

    func expandContext(
        for request: TranslationRequest,
        excluding existingResult: TranslationResult
    ) async throws -> ContextExpansionResult {
        await probe.recordExpand()
        if let error { throw error }
        return ContextExpansionResult(
            requestID: request.id,
            senses: [.init(label: "网络", meaning: "过度自我关注", example: nil)]
        )
    }
}
