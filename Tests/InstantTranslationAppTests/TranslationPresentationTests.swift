import AppKit
import XCTest
import InstantTranslationCore
import InstantTranslationInfrastructure
@testable import InstantTranslationApp

@MainActor
final class TranslationPresentationTests: XCTestCase {
    func testBundledProviderLogosResolveToDistinctTemplateSVGImages() throws {
        let expectedFiles: [(ProviderBrand, String)] = [
            (.googleTranslate, "googletranslate.svg"),
            (.openAI, "openai.svg"),
            (.deepSeek, "deepseek.svg"),
            (.openRouter, "openrouter.svg"),
        ]
        var resolvedURLs = Set<URL>()

        for (brand, expectedFile) in expectedFiles {
            let logo = try XCTUnwrap(BundledProviderLogoLoader.logo(for: brand))

            XCTAssertEqual(logo.resourceURL.lastPathComponent, expectedFile)
            XCTAssertEqual(logo.resourceURL.pathExtension, "svg")
            XCTAssertGreaterThan(logo.image.size.width, 0)
            XCTAssertGreaterThan(logo.image.size.height, 0)
            XCTAssertTrue(logo.image.isTemplate)
            resolvedURLs.insert(logo.resourceURL.standardizedFileURL)
        }

        XCTAssertEqual(resolvedURLs.count, expectedFiles.count)
        XCTAssertNil(BundledProviderLogoLoader.logo(for: .genericAI))
    }

    func testMissingBundledProviderLogoReturnsNilForSafeSymbolFallback() {
        let bundleWithoutProviderLogos = Bundle(for: TranslationPresentationTests.self)

        XCTAssertNil(
            BundledProviderLogoLoader.logo(
                for: .openAI,
                bundle: bundleWithoutProviderLogos
            )
        )
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

    func testSuccessfulCopyFeedbackExpiresAfterDuration() async {
        let controller = CopyController(
            pasteboard: FakePasteboard(),
            feedbackDuration: .milliseconds(20)
        )
        let result = makeResult(providerID: .google, primaryText: "编译器")

        controller.copy(result)
        try? await Task.sleep(for: .milliseconds(40))

        XCTAssertNil(controller.copiedProviderID)
    }

    func testRepeatedCopyKeepsFreshFeedbackForTheFullDuration() async {
        let controller = CopyController(
            pasteboard: FakePasteboard(),
            feedbackDuration: .milliseconds(40)
        )
        let google = makeResult(providerID: .google, primaryText: "编译器")
        let updatedGoogle = makeResult(providerID: .google, primaryText: "编译器")

        controller.copy(google)
        try? await Task.sleep(for: .milliseconds(25))
        controller.copy(updatedGoogle)
        try? await Task.sleep(for: .milliseconds(25))

        XCTAssertEqual(controller.copiedProviderID, .google)

        try? await Task.sleep(for: .milliseconds(30))
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
