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
