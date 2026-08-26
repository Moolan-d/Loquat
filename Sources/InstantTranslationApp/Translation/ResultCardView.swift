import SwiftUI
import InstantTranslationCore
import InstantTranslationFeature
import InstantTranslationInfrastructure

enum TranslationPresentationStyle {
    static let copyFailureColor = NSColor.systemRed
}

/// 卡片正文的高度上限，两张卡各一份。溢出在这里被关进卡片内部，
/// 弹窗本身因此不需要再有一个跨卡片的滚动区。
///
/// 两个数字不是各自独立的偏好：外层滚动没了之后，超过弹窗上限的内容就是够不着的，
/// 所以「两者之和 + 卡片框架 + 输入框长到三行」必须仍然装得进 560。
/// TranslationPopoverLayoutTests 会实测这条不变量，改动任一个数字都得先过那一关。
enum TranslationResultLayout {
    /// Google 只有一段译文。短词自然是一行；长句先撑到约四行，再往下自己滚。
    static let googleBodyMaximumHeight: CGFloat = 96
    /// LLM 卡装着译文、说明、义项、搭配和按需语境，剩下的预算全给它。
    static let llmBodyMaximumHeight: CGFloat = 264
}

@MainActor
public struct ResultCardView: View {
    private let providerID: ProviderID
    private let state: ProviderCardState
    private let llmBrand: ProviderBrand
    private let isConfigured: Bool
    private let contextExpansionState: ContextExpansionState
    @Bindable private var copyController: CopyController
    private let retry: () -> Void
    private let requestMoreContexts: () -> Void
    private let openSettings: @MainActor () -> Void

    public init(
        providerID: ProviderID,
        state: ProviderCardState,
        llmBrand: ProviderBrand,
        isConfigured: Bool = true,
        contextExpansionState: ContextExpansionState = .unavailable,
        copyController: CopyController,
        retry: @escaping () -> Void,
        requestMoreContexts: @escaping () -> Void = {},
        openSettings: @escaping @MainActor () -> Void = {
            NotificationCenter.default.post(
                name: .openInstantTranslationSettings,
                object: nil
            )
        }
    ) {
        self.providerID = providerID
        self.state = state
        self.llmBrand = llmBrand
        self.isConfigured = isConfigured
        self.contextExpansionState = contextExpansionState
        self.copyController = copyController
        self.retry = retry
        self.requestMoreContexts = requestMoreContexts
        self.openSettings = openSettings
    }

    private var displayName: String {
        TranslationResultsPresentation.displayName(
            providerID: providerID,
            llmBrand: llmBrand
        )
    }

    private var idleStatus: TranslationIdleStatus {
        TranslationResultsPresentation.idleStatus(isConfigured: isConfigured)
    }

    public var body: some View {
        Group {
            switch state {
            case .idle:
                // 空闲卡片显示服务名与就绪状态，让“已配置未输入”明显区别于未配置的初始态。
                HStack(spacing: 8) {
                    ProviderIconView(providerID: providerID, llmBrand: llmBrand)
                    Text(displayName)
                        .font(.callout)
                    Spacer()
                    Text(idleStatus.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if idleStatus.showsSetUpAction {
                        Button("Set Up", action: openSettings)
                            .controlSize(.small)
                    }
                }
            case .loading:
                HStack(spacing: 8) {
                    ProviderIconView(providerID: providerID, llmBrand: llmBrand)
                    Text(displayName)
                        .font(.callout)
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(
                            TranslationAccessibility.loadingLabel(providerID: providerID)
                        )
                    Spacer()
                }
            case .success(let result):
                successBody(result)
            case .failure(_, let error):
                HStack(alignment: .top) {
                    ProviderIconView(providerID: providerID, llmBrand: llmBrand)
                    Text(message(for: error))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry", action: retry)
                        .controlSize(.small)
                        .accessibilityLabel(
                            TranslationAccessibility.retryLabel(providerID: providerID)
                        )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            TranslationAccessibility.cardLabel(
                providerID: providerID,
                state: cardAccessibilityState
            )
        )
        .accessibilityValue(cardAccessibilityState == .idle ? idleStatus.message : "")
    }

    /// 两家 provider 的成功态长得不一样，因为它们给的东西本来就不一样：
    /// Google 只有一段译文，LLM 还带着说明、义项、搭配和按需语境。
    /// 硬塞进同一套布局，短的那张就会被长的那张的骨架撑得空荡荡。
    @ViewBuilder
    private func successBody(_ result: TranslationResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 富布局认 LLM，不认「非 Google」：义项、说明、按需语境都是 LLM 才有的产物，
            // 将来多一家只回译文的服务，它该走的是紧凑那条路。
            if providerID == .llm {
                HStack {
                    ProviderIconView(providerID: providerID, llmBrand: llmBrand)
                    Spacer()
                    copyButton(for: result)
                }
                CardBodyScrollView(
                    maximumHeight: TranslationResultLayout.llmBodyMaximumHeight
                ) {
                    LLMResultContentView(
                        result: result,
                        contextExpansionState: contextExpansionState,
                        requestMoreContexts: requestMoreContexts
                    )
                }
            } else {
                // 一行里最高的是复制按钮，译文只有一行时若不夹紧就会被拉到按钮那么高，
                // 文字贴着顶、底下空一截。夹紧之后三者按中线对齐。
                HStack(alignment: .center, spacing: 8) {
                    ProviderIconView(providerID: providerID, llmBrand: llmBrand)
                    CardBodyScrollView(
                        maximumHeight: TranslationResultLayout.googleBodyMaximumHeight
                    ) {
                        Text(result.primaryText)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    copyButton(for: result)
                }
            }
            if copyController.failedProviderID == providerID {
                Text("Copy failed")
                    .font(.caption)
                    .foregroundStyle(
                        Color(nsColor: TranslationPresentationStyle.copyFailureColor)
                    )
                    .accessibilityLabel(
                        "\(TranslationAccessibility.copyLabel(providerID: providerID)) failed"
                    )
            }
        }
    }

    /// 复制按钮在两套布局里位置不同，但反馈语义必须一模一样，于是只留一份实现。
    private func copyButton(for result: TranslationResult) -> some View {
        Button {
            copyController.copy(result)
        } label: {
            Image(
                systemName: copyController.copiedProviderID == providerID
                    ? "checkmark"
                    : "doc.on.doc"
            )
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(
            TranslationAccessibility.copyLabel(providerID: providerID)
        )
        .accessibilityValue(
            TranslationAccessibility.copyValue(copyAccessibilityState)
        )
    }

    private var cardAccessibilityState: TranslationCardAccessibilityState {
        switch state {
        case .idle:
            .idle
        case .loading:
            .loading
        case .success:
            .success
        case .failure:
            .failure
        }
    }

    private var copyAccessibilityState: TranslationCopyAccessibilityState {
        TranslationAccessibility.copyFeedback(
            providerID: providerID,
            copiedProviderID: copyController.copiedProviderID,
            failedProviderID: copyController.failedProviderID
        )
    }

    private func message(for error: TranslationProviderError) -> String {
        switch error {
        case .unconfigured:
            "Configure this service in Settings."
        case .invalidCredentials:
            "Check the API key."
        case .rateLimited:
            "Rate limit reached. Try again later."
        case .networkUnavailable:
            "Network unavailable."
        case .timedOut:
            "Request timed out."
        case .insecureEndpoint:
            "The Base URL is not allowed."
        case .invalidResponse:
            "The service returned an invalid response."
        case .server(let statusCode):
            "Service error (\(statusCode))."
        case .cancelled:
            "Request cancelled."
        }
    }
}


/// 只在内容真的超过上限时才滚动的正文容器。
/// ScrollView 在竖直方向是贪心的——给它多少就占多少，于是一个词的译文也会把
/// 卡片撑到上限那么高。这里量一次内容的自然高度，没超过上限就照实收窄。
private struct CardBodyScrollView<Content: View>: View {
    let maximumHeight: CGFloat
    @ViewBuilder let content: Content

    @State private var contentHeight: CGFloat?

    var body: some View {
        ScrollView(.vertical) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    contentHeight = height
                }
        }
        // 首帧还没量到高度，此时不设限，免得内容被压成 0 闪一下。
        .frame(height: contentHeight.map { min($0, maximumHeight) })
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// LLM 卡的正文全部内容。顺序即信息优先级：先给答案，再给理由，
/// 再给分义项的展开，最后才是要花一次额外请求才拿得到的东西。
private struct LLMResultContentView: View {
    let result: TranslationResult
    let contextExpansionState: ContextExpansionState
    let requestMoreContexts: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.primaryText)
                .font(.body.weight(.semibold))
                .textSelection(.enabled)
            if let rationale = result.rationale, !rationale.isEmpty {
                Text(rationale)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if !result.senses.isEmpty {
                Divider()
                SenseRowsView(senses: result.senses)
            }
            let phrases = TranslationResultsPresentation.visiblePhrases(result)
            if !phrases.isEmpty {
                Divider()
                Text("Common Collocation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(phrases.enumerated()), id: \.offset) { _, phrase in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(phrase.phrase)
                            .font(.callout.weight(.medium))
                        Text(phrase.meaning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ContextExpansionSectionView(
                state: contextExpansionState,
                requestMoreContexts: requestMoreContexts
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 正文不进复制按钮的范围，但要能划选——想引用某一条时靠手动选中。
        .textSelection(.enabled)
    }
}

/// 义项行的唯一渲染器。首译的义项和按需补充的义项长得必须一样，
/// 否则同一种东西会因为来路不同而显出两副面孔。
private struct SenseRowsView: View {
    let senses: [WordSense]

    /// 标签栏宽度。写成常量而不是让 Grid 按最宽的标签自动定列宽，是因为
    /// 首译义项和「更多语境」义项是上下堆着的两个 SenseRowsView：各自算各自的列宽，
    /// 同一张卡里就会出现两条对不齐的正文左边缘。定死之后两批共用一条竖线。
    ///
    /// 66 大约容得下五个汉字或九个西文字母；label 是模型自由生成的，
    /// 真遇到超长的分类就截断——它是索引，正文的可读宽度不该让给它。
    private static let labelColumnWidth: CGFloat = 66

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(senses.enumerated()), id: \.offset) { _, sense in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // 义项出处用描边小标签而不是加粗正文：它是分类，不是内容，
                    // 视觉上得让位给右边真正要读的释义。
                    Text(sense.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay {
                            Capsule()
                                .stroke(
                                    Color(nsColor: .separatorColor),
                                    lineWidth: 0.5
                                )
                        }
                        // 定宽的是槽位不是标签：胶囊仍按自身内容收紧，只是靠左摆进槽里。
                        .frame(width: Self.labelColumnWidth, alignment: .leading)
                    // 释义、例句、例句译文同属一栏，因此共用一条左边缘；
                    // 标签退到槽位里，读的时候视线只需要跟着一条竖线往下走。
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sense.meaning)
                            .font(.caption)
                        if let example = sense.example, !example.isEmpty {
                            // 原文排斜体、译文不排：一眼能分出哪句是要学的，哪句是帮着看懂的。
                            Text(example)
                                .font(.caption)
                                .italic()
                                .foregroundStyle(.secondary)
                            if let translation = sense.exampleTranslation, !translation.isEmpty {
                                Text(translation)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// 按需语境的五种状态。它整块留在 LLM 卡的滚动区里，
/// 这样点开之后长出来的内容只在这张卡内部滚，输入框和 Google 卡都不会动。
private struct ContextExpansionSectionView: View {
    let state: ContextExpansionState
    let requestMoreContexts: () -> Void

    var body: some View {
        switch state {
        case .unavailable:
            EmptyView()
        case .available:
            Divider()
            actionRow
        case .loading:
            Divider()
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Generating more contexts…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .success(let expansion):
            Divider()
            if expansion.senses.isEmpty {
                Text("No additional contexts found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("More Contexts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SenseRowsView(senses: expansion.senses)
            }
        case .failure:
            Divider()
            HStack(spacing: 6) {
                Text("Could not load more contexts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Retry", action: requestMoreContexts)
                    .controlSize(.small)
                    .accessibilityLabel("Retry generating more contexts")
            }
        }
    }

    /// 整行可点而不是只有文字可点：这一行是个入口，热区就该是整条。
    private var actionRow: some View {
        Button(action: requestMoreContexts) {
            HStack {
                Image(systemName: "sparkles")
                VStack(alignment: .leading, spacing: 1) {
                    Text("More Contexts")
                        .font(.callout)
                    Text("Generated on demand by AI")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Generate more contexts with AI")
        .help("Sends one additional LLM request")
    }
}
