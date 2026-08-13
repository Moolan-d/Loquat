import Observation
import XCTest
import InstantTranslationCore
@testable import InstantTranslationFeature

@MainActor
final class TranslationStressTests: XCTestCase {
    func testTwoHundredStubTranslationsRetainOnlyLatestTwoProviderResults() async throws {
        let google = RecordingImmediateProvider(id: .google)
        let llm = RecordingImmediateProvider(id: .llm)
        let session = TranslationSession(
            coordinator: TranslationCoordinator(providers: [google, llm]),
            promptPresetID: .technologyAndRnD
        )
        var firstRequestID: UUID?

        for index in 0..<200 {
            let input = "term-\(index)"
            session.submit(rawText: input, sourceID: .manual)
            let requestID = try XCTUnwrap(session.activeRequest?.id)
            firstRequestID = firstRequestID ?? requestID

            // Observation 变化直接推进等待，避免用固定 sleep 猜测并发任务何时完成。
            await ObservationWaiter.wait {
                Self.result(in: session, providerID: .google)?.requestID == requestID
                    && Self.result(in: session, providerID: .llm)?.requestID == requestID
            }
        }

        let latestRequest = try XCTUnwrap(session.activeRequest)
        XCTAssertEqual(session.input, "term-199")
        XCTAssertEqual(latestRequest.text, "term-199")
        XCTAssertEqual(session.states.count, 2)
        XCTAssertEqual(Set(session.states.keys), Set([.google, .llm]))
        XCTAssertEqual(
            Self.result(in: session, providerID: .google)?.primaryText,
            "google-cloud-translation:term-199"
        )
        XCTAssertEqual(
            Self.result(in: session, providerID: .llm)?.primaryText,
            "openai-compatible-llm:term-199"
        )
        let googleInputs = await google.recordedInputs()
        let llmInputs = await llm.recordedInputs()
        XCTAssertEqual(googleInputs, (0..<200).map { "term-\($0)" })
        XCTAssertEqual(llmInputs, (0..<200).map { "term-\($0)" })

        let staleRequestID = try XCTUnwrap(firstRequestID)
        session.receive(.success(Self.makeResult(
            providerID: .google,
            requestID: staleRequestID,
            input: "stale"
        )))
        XCTAssertEqual(
            Self.result(in: session, providerID: .google)?.requestID,
            latestRequest.id,
            "A completion from an older generation must not replace the current card"
        )
        XCTAssertEqual(
            Self.result(in: session, providerID: .google)?.primaryText,
            "google-cloud-translation:term-199"
        )
        session.cancelAll()
    }

    private static func result(
        in session: TranslationSession,
        providerID: ProviderID
    ) -> TranslationResult? {
        guard case .success(let result)? = session.states[providerID] else { return nil }
        return result
    }

    private static func makeResult(
        providerID: ProviderID,
        requestID: UUID,
        input: String
    ) -> TranslationResult {
        TranslationResult(
            providerID: providerID,
            requestID: requestID,
            primaryText: "\(providerID.rawValue):\(input)",
            rationale: nil,
            sourceLanguage: .english,
            targetLanguage: .simplifiedChinese,
            pronunciations: [],
            speakableText: "\(providerID.rawValue):\(input)",
            duration: .zero
        )
    }
}

private enum ObservationWaiter {
    @MainActor
    static func wait(
        _ condition: @escaping @MainActor @Sendable () -> Bool
    ) async {
        await withCheckedContinuation { continuation in
            ObservationAwaiter(
                condition: condition,
                continuation: continuation
            ).start()
        }
    }
}

@MainActor
private final class ObservationAwaiter {
    private let condition: @MainActor @Sendable () -> Bool
    private let continuation: CheckedContinuation<Void, Never>

    init(
        condition: @escaping @MainActor @Sendable () -> Bool,
        continuation: CheckedContinuation<Void, Never>
    ) {
        self.condition = condition
        self.continuation = continuation
    }

    func start() {
        if condition() {
            continuation.resume()
            return
        }

        withObservationTracking {
            _ = condition()
        } onChange: {
            Task { @MainActor [self] in
                start()
            }
        }
    }
}

private actor RecordingImmediateProvider: TranslationProvider {
    nonisolated let id: ProviderID
    private(set) var inputs: [String] = []

    init(id: ProviderID) {
        self.id = id
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        inputs.append(request.text)
        return TranslationResult(
            providerID: id,
            requestID: request.id,
            primaryText: "\(id.rawValue):\(request.text)",
            rationale: nil,
            sourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage,
            pronunciations: [],
            speakableText: "\(id.rawValue):\(request.text)",
            duration: .zero
        )
    }

    func recordedInputs() -> [String] {
        inputs
    }
}
