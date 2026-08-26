import XCTest
import InstantTranslationCore
@testable import InstantTranslationFeature

@MainActor
final class TranslationSessionTests: XCTestCase {
    func testNewRequestCancelsOldProviderThroughTerminatedStream() async throws {
        let provider = CancellationRecordingProvider(id: .google)
        let session = makeSession(provider: provider)
        session.submit(rawText: "old", sourceID: .manual)
        let oldID = try XCTUnwrap(session.activeRequest?.id)
        let oldStarted = await eventually { await provider.hasStarted(requestID: oldID) }
        XCTAssertTrue(oldStarted, "Old provider call did not start")

        session.submit(rawText: "new", sourceID: .manual)
        let newID = try XCTUnwrap(session.activeRequest?.id)
        let oldCancelled = await eventually { await provider.wasCancelled(requestID: oldID) }
        let oldIsPending = await provider.isPending(requestID: oldID)
        let newStarted = await eventually { await provider.hasStarted(requestID: newID) }

        XCTAssertTrue(oldCancelled, "Replacing the query must cancel the old provider task")
        XCTAssertFalse(oldIsPending)
        XCTAssertTrue(newStarted, "The replacement provider call did not start")
        XCTAssertEqual(session.states[.google], .loading(requestID: newID))

        session.cancelAll()
        _ = await eventually { await provider.wasCancelled(requestID: newID) }
        await provider.releaseAll()
    }

    func testDifferentInputCancelsOldSessionAndRejectsLateEvents() throws {
        let session = makeSession()
        session.submit(rawText: "old", sourceID: .manual)
        let oldID = try XCTUnwrap(session.activeRequest?.id)

        session.submit(rawText: "new", sourceID: .manual)
        let newID = try XCTUnwrap(session.activeRequest?.id)
        session.receive(.success(Self.result(providerID: .google, requestID: oldID, text: "stale")))

        XCTAssertNotEqual(oldID, newID)
        XCTAssertEqual(session.states[.google], .loading(requestID: newID))
        session.cancelAll()
    }

    func testResetClearsInputResultsAndActiveRequest() throws {
        let session = makeSession()
        session.submit(rawText: "compiler", sourceID: .manual)
        let requestID = try XCTUnwrap(session.activeRequest?.id)
        session.receive(.success(Self.result(providerID: .google, requestID: requestID, text: "编译器")))
        XCTAssertEqual(session.states[.google], .success(Self.result(
            providerID: .google, requestID: requestID, text: "编译器"
        )))

        session.reset()

        XCTAssertEqual(session.input, "")
        XCTAssertNil(session.activeRequest)
        XCTAssertEqual(session.states[.google], .idle)
        XCTAssertEqual(session.states[.llm], .idle)
        XCTAssertFalse(session.requiresManualClipboardConfirmation)
    }

    func testResetClearsPendingClipboardConfirmation() throws {
        let session = makeSession()
        let longText = String(repeating: "字", count: 600)
        let source = try XCTUnwrap(SourceText(rawValue: longText, sourceID: .clipboard))
        session.applyClipboardDecision(.requireConfirmation(source))
        XCTAssertTrue(session.requiresManualClipboardConfirmation)

        session.reset()

        XCTAssertEqual(session.input, "")
        XCTAssertFalse(session.requiresManualClipboardConfirmation)
    }

    func testResetRejectsLateEventsFromTheClearedRequest() throws {
        let session = makeSession()
        session.submit(rawText: "compiler", sourceID: .manual)
        let requestID = try XCTUnwrap(session.activeRequest?.id)

        session.reset()
        // 清空后迟到的结果不能把卡片又点亮，否则界面看起来没被重置。
        session.receive(.success(Self.result(providerID: .google, requestID: requestID, text: "stale")))

        XCTAssertEqual(session.states[.google], .idle)
    }

    func testSwapReversesActiveDirectionAndMarksItManual() throws {
        let session = makeSession()
        session.submit(rawText: "compiler", sourceID: .manual)

        session.swapDirectionAndResubmit()

        let request = try XCTUnwrap(session.activeRequest)
        XCTAssertEqual(request.sourceLanguage, .simplifiedChinese)
        XCTAssertEqual(request.targetLanguage, .english)
        XCTAssertEqual(request.directionOrigin, .manual)
        session.cancelAll()
    }

    func testRetryChangesOnlySelectedProviderCard() throws {
        let session = makeSession()
        session.submit(rawText: "compiler", sourceID: .manual)
        let requestID = try XCTUnwrap(session.activeRequest?.id)
        session.receive(.success(Self.result(
            providerID: .llm,
            requestID: requestID,
            text: "编译器"
        )))

        session.retry(providerID: .google)

        XCTAssertEqual(session.states[.google], .loading(requestID: requestID))
        guard case .success(let retained)? = session.states[.llm] else {
            return XCTFail("LLM result must remain visible")
        }
        XCTAssertEqual(retained.primaryText, "编译器")
        session.cancelAll()
    }

    func testRetryRunsWhenCompletionIsIgnored() async throws {
        let provider = GenerationControlledProvider(id: .google)
        let session = makeSession(provider: provider)
        session.submit(rawText: "compiler", sourceID: .manual)
        let requestID = try XCTUnwrap(session.activeRequest?.id)
        let initialCallStarted = await eventually { await provider.callCount == 1 }
        XCTAssertTrue(initialCallStarted)

        session.retry(providerID: .google)
        let retryStarted = await eventually { await provider.callCount == 2 }
        XCTAssertTrue(retryStarted)
        let retryRequestID = await provider.requestID(generation: 1)
        XCTAssertEqual(retryRequestID, requestID)

        await provider.complete(generation: 1, text: "ignored completion")
        let retryPublished = await eventually {
            session.states[.google]?.primaryText == "ignored completion"
        }
        XCTAssertTrue(retryPublished)

        await stop(session: session, provider: provider)
    }

    func testNewestRetryWinsWhenCancelledRetryReturnsLate() async throws {
        let provider = GenerationControlledProvider(id: .google)
        let session = makeSession(provider: provider)
        session.submit(rawText: "compiler", sourceID: .manual)
        let requestID = try XCTUnwrap(session.activeRequest?.id)
        let initialCallStarted = await eventually { await provider.callCount == 1 }
        XCTAssertTrue(initialCallStarted)

        let retryA = try XCTUnwrap(session.retry(providerID: .google))
        let retryAStarted = await eventually { await provider.callCount == 2 }
        XCTAssertTrue(retryAStarted)
        let retryB = try XCTUnwrap(session.retry(providerID: .google))
        let retryBStarted = await eventually { await provider.callCount == 3 }
        XCTAssertTrue(retryBStarted)

        let retryARequestID = await provider.requestID(generation: 1)
        let retryBRequestID = await provider.requestID(generation: 2)
        XCTAssertEqual(retryARequestID, requestID)
        XCTAssertEqual(retryBRequestID, requestID)
        await provider.complete(generation: 2, text: "retry B")
        await retryB.wait()
        XCTAssertEqual(session.states[.google]?.primaryText, "retry B")

        await provider.complete(generation: 1, text: "retry A")
        await retryA.wait()

        XCTAssertEqual(session.states[.google]?.primaryText, "retry B")

        await stop(session: session, provider: provider)
    }

    func testOldRetryEventIsIgnoredAfterNewQueryStarts() async throws {
        let provider = GenerationControlledProvider(id: .google)
        let session = makeSession(provider: provider)
        session.submit(rawText: "old", sourceID: .manual)
        let oldID = try XCTUnwrap(session.activeRequest?.id)
        let initialCallStarted = await eventually { await provider.callCount == 1 }
        XCTAssertTrue(initialCallStarted)
        let oldRetry = try XCTUnwrap(session.retry(providerID: .google))
        let oldRetryStarted = await eventually { await provider.callCount == 2 }
        XCTAssertTrue(oldRetryStarted)

        session.submit(rawText: "new", sourceID: .manual)
        let newID = try XCTUnwrap(session.activeRequest?.id)
        XCTAssertNotEqual(oldID, newID)
        let newCallStarted = await eventually { await provider.callCount == 3 }
        XCTAssertTrue(newCallStarted)

        await provider.complete(generation: 1, text: "stale retry")
        await oldRetry.wait()

        XCTAssertEqual(session.states[.google], .loading(requestID: newID))

        await stop(session: session, provider: provider)
    }

    func testDuplicateClipboardTextDoesNotStartANewRequest() throws {
        let session = makeSession()
        session.submit(rawText: "compiler", sourceID: .manual)
        let firstID = try XCTUnwrap(session.activeRequest?.id)
        let clipboard = try XCTUnwrap(SourceText(rawValue: "compiler", sourceID: .clipboard))

        session.applyClipboardDecision(.translate(clipboard))

        XCTAssertEqual(session.activeRequest?.id, firstID)
        session.cancelAll()
    }

    func testSelectedPromptIsCopiedIntoRequest() {
        let session = makeSession(promptPresetID: .general)

        session.submit(rawText: "compiler", sourceID: .manual)

        XCTAssertEqual(session.activeRequest?.promptPresetID, .general)
        session.cancelAll()
    }

    func testHiddenProviderIsNeitherRequestedNorRetried() async throws {
        let google = CancellationRecordingProvider(id: .google)
        let llm = CancellationRecordingProvider(id: .llm)
        let session = TranslationSession(
            coordinator: TranslationCoordinator(providers: [google, llm]),
            promptPresetID: .technologyAndRnD,
            enabledProviderIDs: [.llm]
        )

        session.submit(rawText: "compiler", sourceID: .manual)
        let requestID = try XCTUnwrap(session.activeRequest?.id)
        let llmStarted = await eventually { await llm.hasStarted(requestID: requestID) }

        XCTAssertTrue(llmStarted)
        let googleStarted = await google.hasStarted(requestID: requestID)
        XCTAssertFalse(googleStarted, "A hidden provider must not receive requests")
        XCTAssertEqual(session.states[.google], .idle)
        XCTAssertEqual(session.states[.llm], .loading(requestID: requestID))
        XCTAssertNil(session.retry(providerID: .google))

        session.cancelAll()
        _ = await eventually { await llm.wasCancelled(requestID: requestID) }
        await google.releaseAll()
        await llm.releaseAll()
    }

    func testDisablingProviderClearsItsCardWithoutTouchingTheOther() throws {
        let session = makeSession()
        session.submit(rawText: "compiler", sourceID: .manual)
        let requestID = try XCTUnwrap(session.activeRequest?.id)
        session.receive(
            .success(Self.result(providerID: .google, requestID: requestID, text: "编译器"))
        )
        session.receive(
            .success(Self.result(providerID: .llm, requestID: requestID, text: "编译程序"))
        )

        session.enabledProviderIDs = [.llm]

        XCTAssertEqual(session.states[.google], .idle)
        XCTAssertEqual(
            session.states[.llm],
            .success(Self.result(providerID: .llm, requestID: requestID, text: "编译程序"))
        )
        session.cancelAll()
    }

    func testMoreContextsBecomesAvailableOnlyAfterALookupSucceedsOnTheLLM() throws {
        let session = makeSession()
        session.submit(rawText: "ego", sourceID: .manual)
        let requestID = try XCTUnwrap(session.activeRequest?.id)
        XCTAssertEqual(session.contextExpansionState, .unavailable)

        // Google 先回来不算数——补充语境是 LLM 的能力。
        session.receive(.success(Self.result(providerID: .google, requestID: requestID, text: "自我")))
        XCTAssertEqual(session.contextExpansionState, .unavailable)

        session.receive(.success(Self.result(providerID: .llm, requestID: requestID, text: "自我")))
        XCTAssertEqual(session.contextExpansionState, .available)
        session.cancelAll()
    }

    func testSentenceTranslationNeverOffersMoreContexts() throws {
        let session = makeSession()
        session.submit(rawText: "the compiler translates source code", sourceID: .manual)
        let requestID = try XCTUnwrap(session.activeRequest?.id)

        session.receive(.success(Self.result(providerID: .llm, requestID: requestID, text: "编译器…")))

        // 整句翻译没有「更多语境」可言，入口根本不该出现。
        XCTAssertEqual(session.contextExpansionState, .unavailable)
        session.cancelAll()
    }

    func testOneClickSendsOneExpansionAndRepeatClicksSendNone() async throws {
        let probe = ExpansionProbe()
        let session = makeSession(provider: ExpandableStubProvider(probe: probe))
        let requestID = try await lookupSucceeded(session)

        session.requestMoreContexts()
        XCTAssertEqual(session.contextExpansionState, .loading)
        // 加载中再点不该叠加请求。
        session.requestMoreContexts()

        let arrived = await eventually {
            if case .success = session.contextExpansionState { return true }
            return false
        }
        XCTAssertTrue(arrived)
        guard case .success(let expansion) = session.contextExpansionState else {
            return XCTFail("Expected the expansion to succeed")
        }
        XCTAssertEqual(expansion.requestID, requestID)
        XCTAssertEqual(expansion.senses.map(\.label), ["网络"])

        // 成功之后的重复点击命中内存里的结果，同样不发请求。
        session.requestMoreContexts()
        let calls = await probe.expandCallCount
        XCTAssertEqual(calls, 1)
        session.cancelAll()
    }

    func testExpansionFailureKeepsTheTranslationAndAllowsExactlyOneRetry() async throws {
        let probe = ExpansionProbe()
        let session = makeSession(
            provider: ExpandableStubProvider(probe: probe, error: .rateLimited)
        )
        _ = try await lookupSucceeded(session)

        session.requestMoreContexts()
        let failed = await eventually {
            session.contextExpansionState == .failure
        }

        XCTAssertTrue(failed)
        // 补充语境失败不该影响已经拿到的译文。
        XCTAssertEqual(session.states[.llm]?.primaryText, "自我")

        session.requestMoreContexts()
        _ = await eventually { await probe.expandCallCount == 2 }
        let calls = await probe.expandCallCount
        XCTAssertEqual(calls, 2)
        session.cancelAll()
    }

    func testEveryFreshStartClearsTheOldSupplementalContext() async throws {
        for restart in Self.restartsThatInvalidateContext {
            let session = makeSession(provider: ExpandableStubProvider(probe: ExpansionProbe()))
            _ = try await lookupSucceeded(session)
            session.requestMoreContexts()
            _ = await eventually {
                if case .success = session.contextExpansionState { return true }
                return false
            }

            restart.apply(session)

            XCTAssertEqual(
                session.contextExpansionState,
                .unavailable,
                "\(restart.name) must clear the previous expansion"
            )
            session.cancelAll()
        }
    }

    func testLateExpansionFromAnAbandonedRequestIsDropped() async throws {
        let gate = ExpansionGate()
        let session = makeSession(
            provider: ExpandableStubProvider(probe: ExpansionProbe(), gate: gate)
        )
        _ = try await lookupSucceeded(session)
        let expansion = session.requestMoreContexts()
        _ = await eventually { await gate.isWaiting }

        // 请求还挂着的时候换了新输入；随后放行的那份属于上一轮，不能贴上来。
        session.submit(rawText: "beef", sourceID: .manual)
        await gate.release()
        await expansion?.wait()

        // 新一轮有自己的入口状态，唯一不能发生的是上一轮的义项贴了上来。
        if case .success(let stale) = session.contextExpansionState {
            XCTFail("A late expansion from \(stale.requestID) leaked into the new lookup")
        }
        session.cancelAll()
    }

    private static let restartsThatInvalidateContext: [ContextInvalidatingRestart] = [
        .init(name: "new submit") { $0.submit(rawText: "beef", sourceID: .manual) },
        .init(name: "swap") { $0.swapDirectionAndResubmit() },
        .init(name: "reset") { $0.reset() },
        .init(name: "disabling the LLM") { $0.enabledProviderIDs = [.google] },
        .init(name: "retrying the LLM") { $0.retry(providerID: .llm) },
    ]

    /// 走到「LLM 查词已成功」这一步：多数补充语境的测试都从这里开始。
    private func lookupSucceeded(_ session: TranslationSession) async throws -> UUID {
        session.submit(rawText: "ego", sourceID: .manual)
        let requestID = try XCTUnwrap(session.activeRequest?.id)
        let ready = await eventually { session.contextExpansionState == .available }
        XCTAssertTrue(ready, "The lookup did not reach the state that offers more contexts")
        return requestID
    }

    private func makeSession(
        promptPresetID: PromptPresetID = .technologyAndRnD
    ) -> TranslationSession {
        makeSession(
            provider: SleepingProvider(id: .google),
            promptPresetID: promptPresetID
        )
    }

    private func makeSession(
        provider: any TranslationProvider,
        promptPresetID: PromptPresetID = .technologyAndRnD
    ) -> TranslationSession {
        TranslationSession(
            coordinator: TranslationCoordinator(providers: [provider]),
            promptPresetID: promptPresetID
        )
    }

    private func eventually(
        timeout: Duration = .seconds(1),
        condition: () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(1))
        }

        return await condition()
    }

    private func stop(
        session: TranslationSession,
        provider: GenerationControlledProvider
    ) async {
        session.cancelAll()
        await provider.releaseAll()
        _ = await eventually { await provider.allCallsFinished }
    }

    private static func result(
        providerID: ProviderID,
        requestID: UUID,
        text: String
    ) -> TranslationResult {
        TranslationResult(
            providerID: providerID,
            requestID: requestID,
            primaryText: text,
            rationale: nil,
            sourceLanguage: .english,
            targetLanguage: .simplifiedChinese,
            pronunciations: [],
            speakableText: text,
            duration: .zero
        )
    }
}

private extension ProviderCardState {
    var primaryText: String? {
        guard case .success(let result) = self else { return nil }
        return result.primaryText
    }
}

private struct SleepingProvider: TranslationProvider {
    let id: ProviderID

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        try await Task.sleep(for: .seconds(5))
        throw TranslationProviderError.cancelled
    }
}

private actor CancellationRecordingProvider: TranslationProvider {
    nonisolated let id: ProviderID
    private var pending: [UUID: PendingCall] = [:]
    private var cancelledRequestIDs: Set<UUID> = []

    init(id: ProviderID) {
        self.id = id
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[request.id] = PendingCall(request: request, continuation: continuation)
            }
        } onCancel: {
            Task { await self.cancel(requestID: request.id) }
        }
    }

    func hasStarted(requestID: UUID) -> Bool {
        pending[requestID] != nil
    }

    func wasCancelled(requestID: UUID) -> Bool {
        cancelledRequestIDs.contains(requestID)
    }

    func isPending(requestID: UUID) -> Bool {
        pending[requestID] != nil
    }

    func releaseAll() {
        let calls = pending.values
        pending.removeAll()
        for call in calls {
            call.continuation.resume(returning: Self.result(for: call.request, text: "released"))
        }
    }

    private func cancel(requestID: UUID) {
        cancelledRequestIDs.insert(requestID)
        pending.removeValue(forKey: requestID)?.continuation.resume(
            throwing: TranslationProviderError.cancelled
        )
    }

    private static func result(
        for request: TranslationRequest,
        text: String
    ) -> TranslationResult {
        TranslationResult(
            providerID: .google,
            requestID: request.id,
            primaryText: text,
            rationale: nil,
            sourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage,
            pronunciations: [],
            speakableText: text,
            duration: .zero
        )
    }

    private struct PendingCall {
        let request: TranslationRequest
        let continuation: CheckedContinuation<TranslationResult, any Error>
    }
}

private actor GenerationControlledProvider: TranslationProvider {
    nonisolated let id: ProviderID
    private var nextGeneration = 0
    private var pending: [Int: PendingCall] = [:]
    private var requests: [Int: TranslationRequest] = [:]
    private var finishedGenerations: Set<Int> = []

    init(id: ProviderID) {
        self.id = id
    }

    var callCount: Int {
        nextGeneration
    }

    var allCallsFinished: Bool {
        finishedGenerations.count == nextGeneration
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let generation = nextGeneration
        nextGeneration += 1
        requests[generation] = request

        let result = await withCheckedContinuation { continuation in
            pending[generation] = PendingCall(request: request, continuation: continuation)
        }
        finishedGenerations.insert(generation)
        return result
    }

    func requestID(generation: Int) -> UUID? {
        requests[generation]?.id
    }

    func complete(generation: Int, text: String) {
        guard let call = pending.removeValue(forKey: generation) else { return }
        call.continuation.resume(returning: result(for: call.request, text: text))
    }

    func releaseAll() {
        let calls = pending
        pending.removeAll()
        for (generation, call) in calls {
            call.continuation.resume(
                returning: result(for: call.request, text: "released \(generation)")
            )
        }
    }

    private func result(
        for request: TranslationRequest,
        text: String
    ) -> TranslationResult {
        TranslationResult(
            providerID: id,
            requestID: request.id,
            primaryText: text,
            rationale: nil,
            sourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage,
            pronunciations: [],
            speakableText: text,
            duration: .zero
        )
    }

    private struct PendingCall {
        let request: TranslationRequest
        let continuation: CheckedContinuation<TranslationResult, Never>
    }
}


private struct ContextInvalidatingRestart {
    let name: String
    let apply: @MainActor (TranslationSession) -> Void

    init(name: String, apply: @escaping @MainActor (TranslationSession) -> Void) {
        self.name = name
        self.apply = apply
    }
}

actor ExpansionProbe {
    private(set) var expandCallCount = 0

    func record() { expandCallCount += 1 }
}

/// 让补充语境请求停在半路，好测「结果迟到时会不会贴到新一轮上」。
actor ExpansionGate {
    private(set) var isWaiting = false
    private var resume: CheckedContinuation<Void, Never>?

    func wait() async {
        isWaiting = true
        await withCheckedContinuation { resume = $0 }
    }

    func release() {
        resume?.resume()
        resume = nil
        isWaiting = false
    }
}

private struct ExpandableStubProvider: TranslationProvider, ContextExpansionProvider {
    let id = ProviderID.llm
    let probe: ExpansionProbe
    var error: TranslationProviderError?
    var gate: ExpansionGate?

    init(
        probe: ExpansionProbe,
        error: TranslationProviderError? = nil,
        gate: ExpansionGate? = nil
    ) {
        self.probe = probe
        self.error = error
        self.gate = gate
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        TranslationResult(
            providerID: id,
            requestID: request.id,
            primaryText: "自我",
            rationale: nil,
            senses: [.init(label: "心理学", meaning: "自我意识", example: nil)],
            phrases: [],
            sourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage,
            pronunciations: [],
            speakableText: "自我",
            duration: .zero
        )
    }

    func expandContext(
        for request: TranslationRequest,
        excluding existingResult: TranslationResult
    ) async throws -> ContextExpansionResult {
        await probe.record()
        await gate?.wait()
        if let error { throw error }
        return ContextExpansionResult(
            requestID: request.id,
            senses: [.init(label: "网络", meaning: "自恋", example: nil)]
        )
    }
}
