import AppKit
import SwiftUI
import XCTest
import InstantTranslationCore
import InstantTranslationFeature
@testable import InstantTranslationApp

/// 弹窗的高度与滚动归属是这次改版的两条主线，而它们都只在真正布局之后才成立：
/// 光看视图代码判断不出「谁在滚」。这里把 TranslationView 挂进真实的 NSWindow
/// 量一遍，用的是仓库里已有的 NSHostingView 手法，不引入快照或 ViewInspector 依赖。
@MainActor
final class TranslationPopoverLayoutTests: XCTestCase {
    func testDefaultLookupFitsThePopoverWithoutAResultsLevelScroller() async throws {
        let session = try await lookupSession(
            googleText: "自我",
            llm: Self.egoResult
        )
        let host = render(session)

        XCTAssertLessThanOrEqual(
            host.fittingSize.height,
            PopoverContentMetrics.standard.maximumHeight
        )

        // 卡片内部可以有滚动区，但不能有任何一个宽到横跨整块结果区——
        // 那就是被删掉的外层滚动又长回来了。
        let cardWidth = TranslationView.contentWidth - Self.popoverHorizontalPadding
        for scroller in resultScrollViews(in: host) {
            XCTAssertLessThanOrEqual(scroller.frame.width, cardWidth)
        }
    }

    func testShortResultsHugTheirContentInsteadOfFillingTheHeightCap() async throws {
        let session = try await lookupSession(
            googleText: "自我",
            llm: Self.result(providerID: .llm, requestID: UUID(), text: "自我")
        )
        let host = render(session)

        // ScrollView 竖直方向是贪心的：给多少占多少。不加约束的话，一个词的译文
        // 也会被撑到整行最高元素（复制按钮）那么高，文字贴着顶、底下空一截。
        for scroller in resultScrollViews(in: host) {
            let content = try XCTUnwrap(scroller.documentView).frame.height
            XCTAssertLessThanOrEqual(
                scroller.frame.height,
                content + 0.5,
                "A short result should hug its content instead of leaving slack"
            )
        }
    }

    func testGoogleAndLLMScrollersStayWithinTheirOwnHeightBudget() async throws {
        let session = try await lookupSession(
            googleText: Self.longText,
            llm: Self.longLLMResult
        )
        let host = render(session)

        let scrollers = resultScrollViews(in: host)
        XCTAssertFalse(scrollers.isEmpty, "Long content should have produced card-local scrollers")
        let budget = max(
            TranslationResultLayout.googleBodyMaximumHeight,
            TranslationResultLayout.llmBodyMaximumHeight
        )
        for scroller in scrollers {
            XCTAssertLessThanOrEqual(scroller.frame.height, budget)
        }
    }

    func testLongContentOverflowsInsideACardInsteadOfGrowingThePopover() async throws {
        let session = try await lookupSession(
            googleText: Self.longText,
            llm: Self.longLLMResult
        )
        let host = render(session)

        XCTAssertLessThanOrEqual(
            host.fittingSize.height,
            PopoverContentMetrics.standard.maximumHeight
        )

        // 至少有一处内容比它的可视区高：溢出确实被关进了卡片，
        // 而不是把弹窗顶高或者悄悄截断。
        let overflowing = resultScrollViews(in: host).contains { scroller in
            guard let document = scroller.documentView else { return false }
            return document.frame.height > scroller.contentView.bounds.height + 0.5
        }
        XCTAssertTrue(overflowing)
    }

    func testWorstCaseContentStillFitsWithTheInputGrownToThreeLines() async throws {
        let session = try await lookupSession(
            googleText: Self.longText,
            llm: Self.longLLMResult
        )
        let host = render(session)

        // 布局测量拿到的是单行输入框；输入框最多还能再长两行，
        // 而那两行同样要从这 560 里出。外层滚动没了之后，超出的部分就是够不着的。
        let inputMetrics = TranslationInputField.fallbackMetrics
        let worstCase = host.fittingSize.height
            + inputMetrics.maximumHeight
            - inputMetrics.minimumHeight

        XCTAssertLessThanOrEqual(
            worstCase,
            PopoverContentMetrics.standard.maximumHeight,
            "The two body caps plus card chrome must leave room for a three-line input"
        )
    }

    // MARK: - Harness

    /// 弹窗左右各 14 的内边距，卡片最宽只到这么宽。
    private static let popoverHorizontalPadding: CGFloat = 28

    private func render(_ session: TranslationSession) -> NSHostingView<TranslationView> {
        let host = NSHostingView(
            rootView: TranslationView(
                session: session,
                appearance: ProviderAppearance(llmBrand: .genericAI),
                availability: ProviderAvailability(configuredProviderIDs: [.google, .llm]),
                focusController: TranslationInputFocusController()
            )
        )
        host.frame = NSRect(
            x: 0,
            y: 0,
            width: TranslationView.contentWidth,
            height: PopoverContentMetrics.standard.maximumHeight
        )
        let window = NSWindow(
            contentRect: host.bounds,
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // 复刻 PopoverContentController 的两趟定尺：先量 fitting，再夹进上下界。
        // 下界 200 才是关键——内容不够高时多出来的空间必须落到某个视图身上，
        // 少了这一趟就看不出是谁把它吃掉了。
        host.frame.size = PopoverContentMetrics.standard.size(
            forFittingHeight: host.fittingSize.height
        )
        host.layoutSubtreeIfNeeded()
        return host
    }

    /// 输入框本身就是个 NSScrollView（三行封顶后要滚），它不属于结果区，
    /// 靠 documentView 是不是 NSTextView 把它认出来并排除。
    private func resultScrollViews(in host: NSView) -> [NSScrollView] {
        allSubviews(of: host)
            .compactMap { $0 as? NSScrollView }
            .filter { !($0.documentView is NSTextView) }
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(allSubviews(of:))
    }

    /// 走到「两张卡都已成功」这一步，好让布局量到的是真实的结果高度。
    private func lookupSession(
        googleText: String,
        llm: TranslationResult
    ) async throws -> TranslationSession {
        let session = TranslationSession(
            coordinator: TranslationCoordinator(providers: [
                StubResultProvider(id: .google) { request in
                    Self.result(providerID: .google, requestID: request.id, text: googleText)
                },
                StubResultProvider(id: .llm) { request in
                    Self.rebind(llm, to: request.id)
                },
            ]),
            promptPresetID: .technologyAndRnD
        )
        session.submit(rawText: "ego", sourceID: .manual)

        let ready = await eventually {
            if case .success = session.states[.google], case .success = session.states[.llm] {
                return true
            }
            return false
        }
        XCTAssertTrue(ready, "Both provider cards should have succeeded before measuring layout")
        return session
    }

    private func eventually(
        timeout: Duration = .seconds(1),
        condition: () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock().now + timeout
        while ContinuousClock().now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    // MARK: - Payloads

    /// 计划里那份有代表性的 ego 结果：3 个义项、1 条搭配，双语例句。
    nonisolated private static let egoResult = result(
        providerID: .llm,
        requestID: UUID(),
        text: "自我；自尊心；自负",
        rationale: "心理学术语与日常贬义用法共用同一个词。",
        senses: [
            .init(
                label: "心理学",
                meaning: "自我（意识主体）",
                example: "The ego mediates between impulse and reality.",
                exampleTranslation: "自我在冲动与现实之间起调节作用。"
            ),
            .init(
                label: "日常",
                meaning: "自尊心",
                example: "The rejection bruised his ego.",
                exampleTranslation: "这次拒绝伤了他的自尊心。"
            ),
            .init(
                label: "贬义",
                meaning: "自负、狂妄",
                example: "Her ego makes collaboration difficult.",
                exampleTranslation: "她的自负让合作变得困难。"
            ),
        ],
        phrases: [.init(phrase: "alter ego", meaning: "另一个自我；至交")]
    )

    nonisolated private static let longText = String(
        repeating: "编译器在生成目标代码之前会先完成词法分析、语法分析与语义检查。",
        count: 8
    )

    nonisolated private static let longLLMResult = result(
        providerID: .llm,
        requestID: UUID(),
        text: longText,
        rationale: String(repeating: "这一段说明刻意写得很长，用来把卡片正文撑过高度上限。", count: 6),
        senses: (1...3).map { index in
            .init(
                label: "义项\(index)",
                meaning: String(repeating: "释义文本", count: 12),
                example: String(repeating: "A fairly long English example sentence. ", count: 3),
                exampleTranslation: String(repeating: "一句相当长的中文例句译文。", count: 3)
            )
        },
        phrases: [.init(phrase: "long collocation", meaning: String(repeating: "搭配释义", count: 8))]
    )

    nonisolated private static func result(
        providerID: ProviderID,
        requestID: UUID,
        text: String,
        rationale: String? = nil,
        senses: [WordSense] = [],
        phrases: [PhraseUsage] = []
    ) -> TranslationResult {
        TranslationResult(
            providerID: providerID,
            requestID: requestID,
            primaryText: text,
            rationale: rationale,
            senses: senses,
            phrases: phrases,
            sourceLanguage: .english,
            targetLanguage: .simplifiedChinese,
            pronunciations: [],
            speakableText: text,
            duration: .zero
        )
    }

    /// 载荷是静态常量，requestID 只有真正提交时才知道，这里补上。
    nonisolated private static func rebind(
        _ result: TranslationResult,
        to requestID: UUID
    ) -> TranslationResult {
        Self.result(
            providerID: result.providerID,
            requestID: requestID,
            text: result.primaryText,
            rationale: result.rationale,
            senses: result.senses,
            phrases: result.phrases
        )
    }
}

private struct StubResultProvider: TranslationProvider {
    let id: ProviderID
    let make: @Sendable (TranslationRequest) -> TranslationResult

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        make(request)
    }
}
