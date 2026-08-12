import XCTest
import InstantTranslationCore
@testable import InstantTranslationFeature

@MainActor
final class TranslationSessionTests: XCTestCase {
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

    private func makeSession(
        promptPresetID: PromptPresetID = .technologyAndRnD
    ) -> TranslationSession {
        TranslationSession(
            coordinator: TranslationCoordinator(providers: [ControlledProvider(id: .google)]),
            promptPresetID: promptPresetID
        )
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

private struct ControlledProvider: TranslationProvider {
    let id: ProviderID

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        try await Task.sleep(for: .seconds(5))
        throw TranslationProviderError.cancelled
    }
}
