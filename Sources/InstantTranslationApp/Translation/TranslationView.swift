import SwiftUI
import InstantTranslationCore
import InstantTranslationFeature

@MainActor
public struct TranslationView: View {
    @Bindable private var session: TranslationSession
    @Bindable private var appearance: ProviderAppearance
    @Bindable private var availability: ProviderAvailability
    @State private var copyController: CopyController
    @State private var resolvedInputHeight: CGFloat = TranslationInputField
        .fallbackMetrics
        .minimumHeight
    private let focusController: TranslationInputFocusController
    private let openSettings: @MainActor () -> Void

    public init(
        session: TranslationSession,
        appearance: ProviderAppearance,
        availability: ProviderAvailability,
        focusController: TranslationInputFocusController,
        openSettings: @escaping @MainActor () -> Void = {
            NotificationCenter.default.post(
                name: .openInstantTranslationSettings,
                object: nil
            )
        }
    ) {
        self.session = session
        self.appearance = appearance
        self.availability = availability
        self.focusController = focusController
        self.openSettings = openSettings
        _copyController = State(initialValue: CopyController())
    }

    /// 弹窗内容宽度的唯一来源：`PopoverContentMetrics.standard` 也读它，两处不能各写各的。
    nonisolated static let contentWidth: CGFloat = 370

    private var shownDirection: TranslationDirection {
        if let request = session.activeRequest {
            return TranslationDirection(
                source: request.sourceLanguage,
                target: request.targetLanguage
            )
        }
        return DirectionResolver().resolve(session.input)
    }

    private var emptyStateReason: TranslationEmptyStateReason? {
        TranslationResultsPresentation.emptyStateReason(
            configured: availability.configuredProviderIDs,
            enabled: session.enabledProviderIDs
        )
    }

    public var body: some View {
        VStack(spacing: 10) {
            TranslationHeader(
                direction: shownDirection,
                canReset: TranslationResultsPresentation.canReset(
                    input: session.input,
                    states: session.states
                ),
                reset: {
                    session.reset()
                    // 清空后光标该回到输入框：用户下一步一定是重新输入。
                    focusController.requestFocus()
                },
                swap: { session.swapDirectionAndResubmit() }
            )
            // 提示语当 placeholder 用：摆在输入框旁边时它一直占着一条竖栏，
            // 长文本被挤成窄窄一条；而它本来就只在框还空着的时候有话要说。
            HStack(alignment: .top, spacing: 2) {
                TranslationInputField(
                    text: $session.input,
                    focusController: focusController,
                    onSubmit: {
                        session.submit(rawText: session.input, sourceID: .manual)
                    },
                    onHeightChange: { resolvedInputHeight = $0 }
                )
                .frame(height: resolvedInputHeight)
                // 靠右而不是靠左：靠左时光标正好压在提示语第一个字上，
                // 像是框里已经有字了。右端是空的，让给它。
                .overlay(alignment: .topTrailing) {
                    if session.input.isEmpty {
                        Text("Enter to translate")
                            .font(Font(TranslationInputField.font))
                            .foregroundStyle(.tertiary)
                            .padding(TranslationInputField.textInset)
                            // 点在提示语上应当照样落进输入框；它也不必再报一次可访问性，
                            // 输入框自己已经有标签了。
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                // 清除键的位置常驻：只靠 opacity 藏起来，不参与显隐时的重排。
                // 否则敲下第一个字的瞬间输入框会缩一截，正在打的那行跟着回流。
                Button {
                    session.reset()
                    // 清空后光标该回到输入框：用户下一步一定是重新输入。
                    focusController.requestFocus()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .opacity(session.input.isEmpty ? 0 : 1)
                .disabled(session.input.isEmpty)
                .accessibilityHidden(session.input.isEmpty)
                .accessibilityLabel("Clear input")
                .padding(.trailing, 2)
            }
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            if session.requiresManualClipboardConfirmation {
                Text("Clipboard text exceeds 500 characters. Press Enter to translate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let emptyStateReason {
                TranslationEmptyStateView(
                    reason: emptyStateReason,
                    openSettings: openSettings
                )
            } else {
                // 卡片直接排布，不套外层滚动：溢出归各自卡片内部消化。
                // 结果区整体滚动会把 Google 卡和输入框一起带跑，
                // 而用户滚的其实只是 LLM 那一张的正文。
                VStack(spacing: 10) {
                    ForEach(
                        TranslationResultsPresentation.visibleProviderIDs(
                            enabled: session.enabledProviderIDs
                        ),
                        id: \.self
                    ) { providerID in
                        ResultCardView(
                            providerID: providerID,
                            state: session.states[providerID] ?? .idle,
                            llmBrand: appearance.llmBrand,
                            isConfigured: availability.configuredProviderIDs
                                .contains(providerID),
                            contextExpansionState: providerID == .llm
                                ? session.contextExpansionState
                                : .unavailable,
                            copyController: copyController,
                            retry: { session.retry(providerID: providerID) },
                            requestMoreContexts: { session.requestMoreContexts() },
                            openSettings: openSettings
                        )
                    }
                }
            }
        }
        .padding(14)
        .frame(width: Self.contentWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(.clear)
        .onAppear {
            // SwiftUI 出现时先请求一次；popover 每次展示后仍由 AppKit 桥再次确保焦点。
            focusController.requestFocus()
        }
    }
}

/// 弹窗顶部这一行只放会话级操作：左边重置，右边方向与互换。
/// 两个按钮分置两端，是为了把"清空"和"换方向"隔开——前者不可撤销，后者随手可逆。
private struct TranslationHeader: View {
    let direction: TranslationDirection
    let canReset: Bool
    let reset: () -> Void
    let swap: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: reset) {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            // 没东西可清时禁用：空弹窗的顶栏应当是安静的。
            .disabled(!canReset)
            .accessibilityLabel("Clear input and results")
            .help("Clear input and results")
            Spacer()
            Text("\(shortName(direction.source)) → \(shortName(direction.target))")
            Button(action: swap) {
                Image(systemName: "arrow.left.arrow.right")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Swap translation direction")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func shortName(_ language: LanguageID) -> String {
        language == .simplifiedChinese ? "中" : "英"
    }
}

/// 非 private：输入框的高度策略参与弹窗的整体高度预算，
/// 布局测试要读它的 fallbackMetrics 才能算出最坏情况。
struct TranslationInputField: NSViewRepresentable {
    static let font = NSFont.preferredFont(forTextStyle: .body)
    static let textInset: CGFloat = 4

    /// 行高取排版引擎实际使用的 line fragment 高度：字体的 defaultLineHeight 会差零点几磅，
    /// 三行封顶时正好够露出第四行的一截。inset 与 textContainerInset 同源，
    /// 可见区才落在整行边界上。真实行高只有布局后才知道，这里的值仅用作首帧下限。
    static func metrics(lineHeight: CGFloat) -> TranslationInputMetrics {
        TranslationInputMetrics(
            lineHeight: lineHeight,
            topInset: textInset,
            bottomInset: textInset
        )
    }

    static let fallbackMetrics = metrics(
        lineHeight: NSLayoutManager().defaultLineHeight(for: font)
    )

    @Binding var text: String
    let focusController: TranslationInputFocusController
    let onSubmit: @MainActor () -> Void
    let onHeightChange: @MainActor (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay

        let textView = SubmitOnReturnTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = Self.font
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(
            width: Self.textInset,
            height: Self.textInset
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.setAccessibilityLabel("Text to translate")
        textView.onSubmit = { [weak textView] in
            guard let textView else { return }
            context.coordinator.parent.text = textView.string
            context.coordinator.parent.onSubmit()
        }

        scrollView.documentView = textView
        context.coordinator.textView = textView
        focusController.bind(textView)
        // 首次布局时文本容器宽度还是 0，usedRect 量不出真实行数；
        // 监听 frame 变化，等拿到真实宽度后再回报一次高度。
        textView.postsFrameChangedNotifications = true
        context.coordinator.observeFrameChanges(of: textView)
        // 圆角描边由外层绘制，这里只负责文本与滚动，避免 bezel 与材质背景叠加。
        scrollView.wantsLayer = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.scheduleHeightReport()
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.stopObservingFrameChanges()
        if let textView = coordinator.textView {
            coordinator.parent.focusController.unbind(textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TranslationInputField
        weak var textView: NSTextView?

        init(parent: TranslationInputField) {
            self.parent = parent
        }

        private var frameObserver: NSObjectProtocol?
        private var lastReportedHeight: CGFloat = -1

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            scheduleHeightReport()
        }

        func observeFrameChanges(of textView: NSTextView) {
            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: textView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleHeightReport()
                }
            }
        }

        func stopObservingFrameChanges() {
            if let frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
            }
            frameObserver = nil
        }

        /// 高度回报会写 SwiftUI @State，不能发生在 updateNSView 的同一轮更新里。
        func scheduleHeightReport() {
            Task { @MainActor [weak self] in
                self?.reportHeight()
            }
        }

        /// 用布局管理器实测文本高度与真实行高，换算出外框高度（三行封顶）。
        private func reportHeight() {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let container = textView.textContainer,
                  container.size.width > 0
            else { return }
            layoutManager.ensureLayout(for: container)
            let measured = layoutManager.usedRect(for: container).height
            let metrics = TranslationInputField.metrics(
                lineHeight: firstLineFragmentHeight(layoutManager) ?? measured
            )
            let resolved = metrics.height(forMeasuredTextHeight: measured)
            guard abs(resolved - lastReportedHeight) > 0.5 else { return }
            lastReportedHeight = resolved
            parent.onHeightChange(resolved)
        }

        private func firstLineFragmentHeight(
            _ layoutManager: NSLayoutManager
        ) -> CGFloat? {
            guard layoutManager.numberOfGlyphs > 0 else { return nil }
            var effectiveRange = NSRange()
            let fragment = layoutManager.lineFragmentRect(
                forGlyphAt: 0,
                effectiveRange: &effectiveRange
            )
            return fragment.height > 0 ? fragment.height : nil
        }
    }
}

/// Enter 提交，Shift+Enter 换行。NSTextView 对两者都发 insertNewline:，
/// 只能靠当前事件的修饰键区分，否则多行输入根本敲不出第二行。
@MainActor
final class SubmitOnReturnTextView: NSTextView {
    var onSubmit: (@MainActor () -> Void)?
    /// 默认读当前事件；测试从这里注入修饰键状态。
    var isShiftPressed: @MainActor () -> Bool = {
        NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(NSResponder.insertNewline(_:)), !isShiftPressed() {
            onSubmit?()
            return
        }
        super.doCommand(by: selector)
    }
}
