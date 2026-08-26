import AppKit
import XCTest
import InstantTranslationCore
import InstantTranslationFeature
import InstantTranslationInfrastructure
@testable import InstantTranslationApp

@MainActor
final class TranslationPresentationTests: XCTestCase {
    func testInputFieldHeightGrowsWithContentThenClampsAtThreeLines() {
        let metrics = TranslationInputMetrics(lineHeight: 16, topInset: 4, bottomInset: 4)

        XCTAssertEqual(metrics.height(forMeasuredTextHeight: 0), 24, accuracy: 0.01)
        XCTAssertEqual(metrics.height(forMeasuredTextHeight: 16), 24, accuracy: 0.01)
        XCTAssertEqual(metrics.height(forMeasuredTextHeight: 32), 40, accuracy: 0.01)
        // 三行封顶：可见区正好是三整行，不漏出第四行的顶端。
        XCTAssertEqual(metrics.height(forMeasuredTextHeight: 48), 52, accuracy: 0.01)
        // 超过三行不再增高；余下内容由输入框内部滚动承担，弹窗整体高度保持稳定。
        // 与正好三行同高，越过封顶时输入框不会反而缩一截。
        XCTAssertEqual(metrics.height(forMeasuredTextHeight: 160), 52, accuracy: 0.01)
    }

    func testResetIsDisabledOnlyWhenThereIsNothingToClear() {
        let idle: [ProviderID: ProviderCardState] = [.google: .idle, .llm: .idle]
        XCTAssertFalse(TranslationResultsPresentation.canReset(input: "", states: idle))

        // 只要输入框有字，或任一张卡片不是 idle，就有东西可清。
        XCTAssertTrue(TranslationResultsPresentation.canReset(input: "compiler", states: idle))
        XCTAssertTrue(TranslationResultsPresentation.canReset(
            input: "",
            states: [.google: .loading(requestID: UUID()), .llm: .idle]
        ))
    }

    func testReturnSubmitsWhileShiftReturnInsertsANewline() {
        let textView = SubmitOnReturnTextView()
        var submitCount = 0
        textView.onSubmit = { submitCount += 1 }
        textView.string = "first"

        // 未按 Shift：Enter 提交，不改动文本。
        textView.isShiftPressed = { false }
        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(submitCount, 1)
        XCTAssertEqual(textView.string, "first")

        // 按住 Shift：换行落进文本，不触发提交；否则三行输入框根本敲不出第二行。
        textView.isShiftPressed = { true }
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(submitCount, 1)
        XCTAssertEqual(textView.string, "first\n")
    }

    func testInputFieldCapFloorsFractionalLineHeightsToWholePoints() {
        // 排版引擎给出的真实行高带小数；三行封顶若不向下取整，SwiftUI 的像素对齐
        // 会把外框放大半点，露出第四行的顶端。
        let metrics = TranslationInputMetrics(
            lineHeight: 16.00634765625,
            topInset: 4,
            bottomInset: 4
        )

        XCTAssertEqual(metrics.maximumHeight, 52, accuracy: 0.0001)
        XCTAssertEqual(metrics.height(forMeasuredTextHeight: 128), 52, accuracy: 0.0001)
    }


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

    func testCopyStillTakesOnlyTheTranslationWhenSensesArePresent() {
        let pasteboard = FakePasteboard()
        let controller = CopyController(pasteboard: pasteboard)
        let result = makeResult(
            providerID: .llm,
            primaryText: "牛肉",
            senses: [.init(label: "俚语", meaning: "抱怨、牢骚", example: nil)],
            phrases: [.init(phrase: "beef up", meaning: "加强")]
        )

        controller.copy(result)

        // ⧉ 的含义始终是"把译文拿走"；义项要引用就靠手动划选。
        XCTAssertEqual(pasteboard.value, "牛肉")
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

    func testEmptyStateOnlyAppearsWhenNoVisibleProviderIsConfigured() {
        XCTAssertEqual(
            TranslationResultsPresentation.emptyStateReason(
                configured: [],
                enabled: [.google, .llm]
            ),
            .noProviderConfigured
        )
        XCTAssertEqual(
            TranslationResultsPresentation.emptyStateReason(
                configured: [.google, .llm],
                enabled: []
            ),
            .allProvidersHidden
        )
        XCTAssertEqual(
            TranslationResultsPresentation.emptyStateReason(
                configured: [.google],
                enabled: [.llm]
            ),
            .noProviderConfigured
        )
        XCTAssertNil(
            TranslationResultsPresentation.emptyStateReason(
                configured: [.google],
                enabled: [.google, .llm]
            )
        )
    }

    func testEmptyStateReasonsCarryDistinctCopyAndAction() {
        for reason in [
            TranslationEmptyStateReason.noProviderConfigured,
            TranslationEmptyStateReason.allProvidersHidden,
        ] {
            XCTAssertFalse(reason.title.isEmpty)
            XCTAssertFalse(reason.message.isEmpty)
            XCTAssertFalse(reason.symbolName.isEmpty)
            XCTAssertEqual(reason.actionTitle, "Open Settings…")
        }
        XCTAssertNotEqual(
            TranslationEmptyStateReason.noProviderConfigured.title,
            TranslationEmptyStateReason.allProvidersHidden.title
        )
        XCTAssertNotEqual(
            TranslationEmptyStateReason.noProviderConfigured.symbolName,
            TranslationEmptyStateReason.allProvidersHidden.symbolName
        )
    }

    func testHiddenProvidersLeaveTheWindowInAStableOrder() {
        XCTAssertEqual(
            TranslationResultsPresentation.visibleProviderIDs(enabled: [.llm, .google]),
            [.google, .llm]
        )
        XCTAssertEqual(
            TranslationResultsPresentation.visibleProviderIDs(enabled: [.llm]),
            [.llm]
        )
        XCTAssertEqual(
            TranslationResultsPresentation.visibleProviderIDs(enabled: []),
            []
        )
    }

    func testIdleCardDistinguishesConfiguredFromUnconfiguredProvider() {
        let ready = TranslationResultsPresentation.idleStatus(isConfigured: true)
        let missing = TranslationResultsPresentation.idleStatus(isConfigured: false)

        XCTAssertEqual(ready, .ready)
        XCTAssertEqual(missing, .notConfigured)
        XCTAssertNotEqual(ready.message, missing.message)
        XCTAssertFalse(ready.showsSetUpAction)
        XCTAssertTrue(missing.showsSetUpAction)
    }

    func testIdleCardNamesTheServiceItRepresents() {
        XCTAssertEqual(
            TranslationResultsPresentation.displayName(providerID: .google, llmBrand: .openAI),
            "Google Translate"
        )
        XCTAssertEqual(
            TranslationResultsPresentation.displayName(providerID: .llm, llmBrand: .openAI),
            "OpenAI"
        )
        XCTAssertEqual(
            TranslationResultsPresentation.displayName(providerID: .llm, llmBrand: .deepSeek),
            "DeepSeek"
        )
        XCTAssertEqual(
            TranslationResultsPresentation.displayName(providerID: .llm, llmBrand: .genericAI),
            "LLM"
        )
    }

    func testConfiguredProvidersRequireEveryFieldTheProviderNeeds() {
        XCTAssertEqual(
            ProviderAvailability.configuredProviderIDs(
                googleAPIKey: "google-key",
                llmAPIKey: "llm-key",
                llmBaseURL: "https://api.openai.com/v1",
                llmModel: "gpt-4o-mini"
            ),
            [.google, .llm]
        )
        // LLM 缺 model 时仍然无法翻译，不能算作"已配置"。
        XCTAssertEqual(
            ProviderAvailability.configuredProviderIDs(
                googleAPIKey: "google-key",
                llmAPIKey: "llm-key",
                llmBaseURL: "https://api.openai.com/v1",
                llmModel: ""
            ),
            [.google]
        )
        XCTAssertEqual(
            ProviderAvailability.configuredProviderIDs(
                googleAPIKey: "  ",
                llmAPIKey: "llm-key",
                llmBaseURL: "https://api.openai.com/v1",
                llmModel: "gpt-4o-mini"
            ),
            [.llm]
        )
        XCTAssertEqual(
            ProviderAvailability.configuredProviderIDs(
                googleAPIKey: nil,
                llmAPIKey: nil,
                llmBaseURL: "",
                llmModel: ""
            ),
            []
        )
    }

    func testUnreadableKeychainDoesNotClaimTheProviderIsUnconfigured() {
        struct ReadFailure: Error {}

        // 读不出来只说明状态未知；此时错报"未配置"正是这次要修的误导。
        XCTAssertEqual(
            ProviderAvailability.configuredProviderIDs(
                googleAPIKey: .of(Result<String?, any Error>.failure(ReadFailure())),
                llmAPIKey: .of(Result<String?, any Error>.failure(ReadFailure())),
                llmBaseURL: "https://api.openai.com/v1",
                llmModel: "gpt-4o-mini"
            ),
            [.google, .llm]
        )
        // Base URL/模型来自偏好，读得到就按实际值判断，不受 Keychain 失败影响。
        XCTAssertEqual(
            ProviderAvailability.configuredProviderIDs(
                googleAPIKey: .of(Result<String?, any Error>.failure(ReadFailure())),
                llmAPIKey: .of(Result<String?, any Error>.failure(ReadFailure())),
                llmBaseURL: "",
                llmModel: ""
            ),
            [.google]
        )
        XCTAssertEqual(
            ProviderAvailability.configuredProviderIDs(
                googleAPIKey: .of(Result<String?, any Error>.success(nil)),
                llmAPIKey: .of(Result<String?, any Error>.success(nil)),
                llmBaseURL: "",
                llmModel: ""
            ),
            []
        )
    }

    func testOnlyFirstCollocationIsVisible() {
        let result = makeResult(
            providerID: .llm,
            primaryText: "自我；自尊心；自负",
            phrases: [
                .init(phrase: "alter ego", meaning: "另一个自我"),
                .init(phrase: "ego boost", meaning: "提升自信"),
            ]
        )

        // 解析器已经截到 1 条；视图层再兜一次，因为卡片高度预算只留得下一行。
        XCTAssertEqual(
            TranslationResultsPresentation.visiblePhrases(result).map(\.phrase),
            ["alter ego"]
        )
    }

    func testMoreContextsActionOnlyAppearsWhenAvailableOrFailed() {
        XCTAssertTrue(TranslationResultsPresentation.showsMoreContextsAction(.available))
        XCTAssertTrue(TranslationResultsPresentation.showsMoreContextsAction(.failure))
        XCTAssertFalse(TranslationResultsPresentation.showsMoreContextsAction(.unavailable))
        XCTAssertFalse(TranslationResultsPresentation.showsMoreContextsAction(.loading))
        // 已经拿到结果之后入口就该消失，否则用户会以为还能再要一份。
        XCTAssertFalse(
            TranslationResultsPresentation.showsMoreContextsAction(
                .success(.init(requestID: UUID(), senses: []))
            )
        )
    }

    func testCardBodyHeightCapsLeaveRoomForBothCardsInsideThePopover() {
        // 两张卡的正文上限加上各自的框架开销，必须仍装得进弹窗；
        // 任何一个数字调大都得先在这里过一遍，而不是等真机上撑破了才发现。
        let bodyBudget = TranslationResultLayout.googleBodyMaximumHeight
            + TranslationResultLayout.llmBodyMaximumHeight

        XCTAssertLessThan(bodyBudget, PopoverContentMetrics.standard.maximumHeight)
    }

    private func makeResult(
        providerID: ProviderID,
        requestID: UUID = UUID(),
        primaryText: String,
        rationale: String? = nil,
        senses: [WordSense] = [],
        phrases: [PhraseUsage] = []
    ) -> TranslationResult {
        TranslationResult(
            providerID: providerID,
            requestID: requestID,
            primaryText: primaryText,
            rationale: rationale,
            senses: senses,
            phrases: phrases,
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
