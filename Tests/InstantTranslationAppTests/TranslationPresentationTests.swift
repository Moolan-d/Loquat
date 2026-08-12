import AppKit
import XCTest
import InstantTranslationCore
import InstantTranslationFeature
import InstantTranslationInfrastructure
@testable import InstantTranslationApp

@MainActor
final class TranslationPresentationTests: XCTestCase {
    func testBundledProviderLogosResolveToDistinctTemplateSVGImages() throws {
        let loader = BundledProviderLogoLoader(bundle: .module)
        let expectedFiles: [(ProviderBrand, String)] = [
            (.googleTranslate, "googletranslate.svg"),
            (.openAI, "openai.svg"),
            (.deepSeek, "deepseek.svg"),
            (.openRouter, "openrouter.svg"),
        ]
        var resolvedURLs = Set<URL>()

        for (brand, expectedFile) in expectedFiles {
            let logo = try XCTUnwrap(loader.logo(for: brand))

            XCTAssertEqual(logo.resourceURL.lastPathComponent, expectedFile)
            XCTAssertEqual(logo.resourceURL.pathExtension, "svg")
            XCTAssertGreaterThan(logo.image.size.width, 0)
            XCTAssertGreaterThan(logo.image.size.height, 0)
            XCTAssertTrue(logo.image.isTemplate)
            resolvedURLs.insert(logo.resourceURL.standardizedFileURL)
        }

        XCTAssertEqual(resolvedURLs.count, expectedFiles.count)
        XCTAssertNil(loader.logo(for: .genericAI))
    }

    func testBundledProviderLogoLoaderReusesImageForSameBrand() throws {
        let loader = BundledProviderLogoLoader.shared

        let first = try XCTUnwrap(loader.logo(for: .openAI))
        let second = try XCTUnwrap(loader.logo(for: .openAI))

        XCTAssertTrue(first.image === second.image)
    }

    func testMissingBundledProviderLogoReturnsNilForSafeSymbolFallback() {
        let bundleWithoutProviderLogos = Bundle(for: TranslationPresentationTests.self)
        let loader = BundledProviderLogoLoader(bundle: bundleWithoutProviderLogos)

        XCTAssertNil(loader.logo(for: .openAI))
    }

    func testLLMCopyWritesPrimaryTranslationWithoutRationale() {
        let pasteboard = FakePasteboard()
        let controller = CopyController(pasteboard: pasteboard)
        let result = makeResult(
            providerID: .llm,
            primaryText: "compiler",
            rationale: "Standard term."
        )

        controller.copy(result)

        XCTAssertEqual(pasteboard.value, "compiler")
        XCTAssertEqual(controller.copiedProviderID, .llm)
    }

    func testAccessibilityLabelsAreStable() {
        XCTAssertEqual(
            TranslationAccessibility.copyLabel(providerID: .google),
            "Copy Google translation"
        )
        XCTAssertEqual(
            TranslationAccessibility.copyLabel(providerID: .llm),
            "Copy LLM translation"
        )
    }

    func testProviderIdentityIsPresentForEveryCardState() {
        let expected: [(TranslationCardAccessibilityState, String, String)] = [
            (.idle, "Google translation", "LLM translation"),
            (.loading, "Google translation, loading", "LLM translation, loading"),
            (.success, "Google translation, result", "LLM translation, result"),
            (.failure, "Google translation, failed", "LLM translation, failed"),
        ]

        for (state, google, llm) in expected {
            XCTAssertEqual(
                TranslationAccessibility.cardLabel(providerID: .google, state: state),
                google
            )
            XCTAssertEqual(
                TranslationAccessibility.cardLabel(providerID: .llm, state: state),
                llm
            )
        }
    }

    func testLoadingAndRetryLabelsIdentifyTheirProvider() {
        XCTAssertEqual(
            TranslationAccessibility.loadingLabel(providerID: .google),
            "Google translation loading"
        )
        XCTAssertEqual(
            TranslationAccessibility.loadingLabel(providerID: .llm),
            "LLM translation loading"
        )
        XCTAssertEqual(
            TranslationAccessibility.retryLabel(providerID: .google),
            "Retry Google translation"
        )
        XCTAssertEqual(
            TranslationAccessibility.retryLabel(providerID: .llm),
            "Retry LLM translation"
        )
    }

    func testCopyFeedbackHasVoiceOverValues() {
        XCTAssertEqual(
            TranslationAccessibility.copyFeedback(
                providerID: .google,
                copiedProviderID: .google,
                failedProviderID: nil
            ),
            .copied
        )
        XCTAssertEqual(
            TranslationAccessibility.copyFeedback(
                providerID: .llm,
                copiedProviderID: nil,
                failedProviderID: .llm
            ),
            .failed
        )
        XCTAssertEqual(TranslationAccessibility.copyValue(.idle), "")
        XCTAssertEqual(TranslationAccessibility.copyValue(.copied), "Copied")
        XCTAssertEqual(TranslationAccessibility.copyValue(.failed), "Copy failed")
    }

    func testCopyFailureUsesSemanticSystemColor() {
        XCTAssertEqual(TranslationPresentationStyle.copyFailureColor, .systemRed)
    }

    func testCopyFeedbackMovesIndependentlyBetweenProviderCards() {
        let pasteboard = FakePasteboard()
        let controller = CopyController(pasteboard: pasteboard)
        let requestID = UUID()
        let google = makeResult(
            providerID: .google,
            requestID: requestID,
            primaryText: "编译器"
        )
        let llm = makeResult(
            providerID: .llm,
            requestID: requestID,
            primaryText: "compiler",
            rationale: "Standard term."
        )

        controller.copy(google)
        XCTAssertEqual(controller.copiedProviderID, .google)

        controller.copy(llm)

        XCTAssertEqual(controller.copiedProviderID, .llm)
        XCTAssertEqual(pasteboard.value, "compiler")
    }

    func testFailedPasteboardWriteShowsFailureForThatProvider() {
        let pasteboard = FakePasteboard(succeeds: false)
        let controller = CopyController(pasteboard: pasteboard)
        let result = makeResult(providerID: .google, primaryText: "编译器")

        controller.copy(result)

        XCTAssertNil(controller.copiedProviderID)
        XCTAssertEqual(controller.failedProviderID, .google)
    }

    func testFailedWriteClearsPreviousSuccessFeedback() {
        let pasteboard = FakePasteboard()
        let controller = CopyController(pasteboard: pasteboard)
        controller.copy(makeResult(providerID: .llm, primaryText: "compiler"))
        pasteboard.succeeds = false

        controller.copy(makeResult(providerID: .google, primaryText: "编译器"))

        XCTAssertNil(controller.copiedProviderID)
        XCTAssertEqual(controller.failedProviderID, .google)
    }

    func testSuccessfulWriteClearsPreviousFailureFeedback() {
        let pasteboard = FakePasteboard(succeeds: false)
        let controller = CopyController(pasteboard: pasteboard)
        controller.copy(makeResult(providerID: .google, primaryText: "编译器"))
        pasteboard.succeeds = true

        controller.copy(makeResult(providerID: .llm, primaryText: "compiler"))

        XCTAssertEqual(controller.copiedProviderID, .llm)
        XCTAssertNil(controller.failedProviderID)
    }

    func testSuccessfulCopyFeedbackExpiresAfterScheduledDuration() {
        let scheduler = ManualCopyFeedbackScheduler()
        let controller = CopyController(
            pasteboard: FakePasteboard(),
            scheduler: scheduler
        )
        let result = makeResult(providerID: .google, primaryText: "编译器")

        controller.copy(result)
        XCTAssertEqual(scheduler.scheduledDurations, [.seconds(1.2)])
        XCTAssertEqual(controller.copiedProviderID, .google)

        scheduler.fireNext()

        XCTAssertNil(controller.copiedProviderID)
    }

    func testCancelledOldScheduleCannotClearFreshFeedback() {
        let scheduler = ManualCopyFeedbackScheduler()
        let controller = CopyController(
            pasteboard: FakePasteboard(),
            scheduler: scheduler
        )
        let google = makeResult(providerID: .google, primaryText: "编译器")
        let updatedGoogle = makeResult(providerID: .google, primaryText: "编译器")

        controller.copy(google)
        controller.copy(updatedGoogle)

        scheduler.fireNext()
        XCTAssertEqual(controller.copiedProviderID, .google)

        scheduler.fireNext()
        XCTAssertNil(controller.copiedProviderID)
    }

    private func makeResult(
        providerID: ProviderID,
        requestID: UUID = UUID(),
        primaryText: String,
        rationale: String? = nil
    ) -> TranslationResult {
        TranslationResult(
            providerID: providerID,
            requestID: requestID,
            primaryText: primaryText,
            rationale: rationale,
            sourceLanguage: providerID == .google ? .english : .simplifiedChinese,
            targetLanguage: providerID == .google ? .simplifiedChinese : .english,
            pronunciations: [],
            speakableText: primaryText,
            duration: .zero
        )
    }
}

@MainActor
private final class FakePasteboard: PasteboardWriting {
    var value: String?
    var succeeds: Bool

    init(succeeds: Bool = true) {
        self.succeeds = succeeds
    }

    func write(_ value: String) -> Bool {
        self.value = value
        return succeeds
    }
}

@MainActor
private final class ManualCopyFeedbackScheduler: CopyFeedbackScheduling {
    private struct Pending {
        let cancellation: ManualCopyFeedbackCancellation
        let action: @MainActor () -> Void
    }

    private var pending: [Pending] = []
    private(set) var scheduledDurations: [Duration] = []

    func schedule(
        after duration: Duration,
        action: @escaping @MainActor () -> Void
    ) -> any CopyFeedbackCancellation {
        let cancellation = ManualCopyFeedbackCancellation()
        scheduledDurations.append(duration)
        pending.append(Pending(cancellation: cancellation, action: action))
        return cancellation
    }

    func fireNext() {
        let next = pending.removeFirst()
        guard !next.cancellation.isCancelled else { return }
        next.action()
    }
}

@MainActor
private final class ManualCopyFeedbackCancellation: CopyFeedbackCancellation {
    private(set) var isCancelled = false

    func cancel() {
        isCancelled = true
    }
}
