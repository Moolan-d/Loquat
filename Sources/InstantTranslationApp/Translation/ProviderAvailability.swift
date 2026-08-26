import Observation
import SwiftUI
import InstantTranslationCore
import InstantTranslationFeature
import InstantTranslationInfrastructure

/// 凭据可能读不出来（Keychain 报错），这与"确实没配置"是两回事，必须分开表达。
public enum CredentialPresence: Equatable, Sendable {
    case present
    case absent
    case unknown

    public static func of(_ value: String?) -> CredentialPresence {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .absent
        }
        return .present
    }

    /// 读取失败时按"已配置"呈现：把用户真实存在的配置错报成未配置，
    /// 正是这次要修的误导；真的缺凭据时翻译请求仍会给出可操作的错误。
    public static func of(_ result: Result<String?, any Error>) -> CredentialPresence {
        switch result {
        case .success(let value): of(value)
        case .failure: .unknown
        }
    }

    var countsAsConfigured: Bool {
        self != .absent
    }
}

/// 窗口需要知道“哪些 provider 已经配置好凭据”，但不能在渲染路径上读 Keychain。
/// 因此凭据可用性由启动组合与设置保存显式发布，视图只消费这份快照。
@MainActor
@Observable
public final class ProviderAvailability {
    public var configuredProviderIDs: Set<ProviderID>

    public init(configuredProviderIDs: Set<ProviderID> = []) {
        self.configuredProviderIDs = configuredProviderIDs
    }

    public static func configuredProviderIDs(
        googleAPIKey: String?,
        llmAPIKey: String?,
        llmBaseURL: String,
        llmModel: String
    ) -> Set<ProviderID> {
        configuredProviderIDs(
            googleAPIKey: .of(googleAPIKey),
            llmAPIKey: .of(llmAPIKey),
            llmBaseURL: llmBaseURL,
            llmModel: llmModel
        )
    }

    public static func configuredProviderIDs(
        googleAPIKey: CredentialPresence,
        llmAPIKey: CredentialPresence,
        llmBaseURL: String,
        llmModel: String
    ) -> Set<ProviderID> {
        var configured: Set<ProviderID> = []
        if googleAPIKey.countsAsConfigured {
            configured.insert(.google)
        }
        // Base URL 与模型来自偏好而非 Keychain，始终可读，因此仍然按实际值判断。
        if llmAPIKey.countsAsConfigured,
           CredentialPresence.of(llmBaseURL) == .present,
           CredentialPresence.of(llmModel) == .present {
            configured.insert(.llm)
        }
        return configured
    }
}

/// 空状态的两种成因需要不同的引导文案；策略与视图分离，便于直接断言。
public enum TranslationEmptyStateReason: Equatable, Sendable {
    case noProviderConfigured
    case allProvidersHidden

    public var symbolName: String {
        switch self {
        case .noProviderConfigured: "character.bubble"
        case .allProvidersHidden: "eye.slash"
        }
    }

    public var title: String {
        switch self {
        case .noProviderConfigured: "No translation service yet"
        case .allProvidersHidden: "All translation services hidden"
        }
    }

    public var message: String {
        switch self {
        case .noProviderConfigured:
            "Add a Google or LLM API key in Settings to start translating."
        case .allProvidersHidden:
            "Turn a service back on in Settings to see its results here."
        }
    }

    public var actionTitle: String {
        switch self {
        case .noProviderConfigured: "Open Settings…"
        case .allProvidersHidden: "Open Settings…"
        }
    }

    public var accessibilityLabel: String {
        "\(title). \(message)"
    }
}

public enum TranslationResultsPresentation {
    /// 窗口条目顺序固定，避免开关切换后卡片位置跳动。
    public static let providerOrder: [ProviderID] = [.google, .llm]

    public static func visibleProviderIDs(
        enabled: Set<ProviderID>
    ) -> [ProviderID] {
        providerOrder.filter(enabled.contains)
    }

    public static func emptyStateReason(
        configured: Set<ProviderID>,
        enabled: Set<ProviderID>
    ) -> TranslationEmptyStateReason? {
        // 只有全部开关都关掉才算“被隐藏”；还留着可见条目却没凭据时，该引导用户去配置。
        guard !enabled.isEmpty else { return .allProvidersHidden }
        guard configured.intersection(enabled).isEmpty else { return nil }
        return .noProviderConfigured
    }

    /// 空闲卡片必须显示服务身份，否则“已配置但未输入”和“完全没配置”在窗口里长得一样。
    public static func displayName(
        providerID: ProviderID,
        llmBrand: ProviderBrand
    ) -> String {
        guard providerID != .google else { return "Google Translate" }
        return switch llmBrand {
        case .googleTranslate: "Google Translate"
        case .openAI: "OpenAI"
        case .deepSeek: "DeepSeek"
        case .openRouter: "OpenRouter"
        case .genericAI: "LLM"
        }
    }

    /// 输入与卡片都空时没有可清的东西，重置按钮保持禁用，
    /// 免得界面上摆着一个点下去毫无反应的控件。
    public static func canReset(
        input: String,
        states: [ProviderID: ProviderCardState]
    ) -> Bool {
        !input.isEmpty || states.values.contains { $0 != .idle }
    }

    /// 搭配只显示最有用的那一条。解析器已经截过一次，这里再截一次不是重复：
    /// 卡片的高度预算只留得下一行，视图不该指望上游永远守约。
    public static func visiblePhrases(_ result: TranslationResult) -> [PhraseUsage] {
        Array(result.phrases.prefix(1))
    }

    /// 「更多语境」的入口只在「可以点」的时候出现：还没点过，或者点过但失败了。
    /// 加载中要让位给进度提示，已成功则结果本身就在下面，再摆一个入口只会让人
    /// 以为还能再要一份。
    public static func showsMoreContextsAction(_ state: ContextExpansionState) -> Bool {
        switch state {
        case .available, .failure: true
        case .unavailable, .loading, .success: false
        }
    }

    public static func idleStatus(isConfigured: Bool) -> TranslationIdleStatus {
        isConfigured ? .ready : .notConfigured
    }
}

public enum TranslationIdleStatus: Equatable, Sendable {
    case ready
    case notConfigured

    public var message: String {
        switch self {
        case .ready: "Ready"
        case .notConfigured: "Not configured"
        }
    }

    public var showsSetUpAction: Bool {
        self == .notConfigured
    }
}

@MainActor
struct TranslationEmptyStateView: View {
    let reason: TranslationEmptyStateReason
    let openSettings: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(nsColor: .controlAccentColor).opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: reason.symbolName)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(Color(nsColor: .controlAccentColor))
            }
            .accessibilityHidden(true)
            Text(reason.title)
                .font(.headline)
            Text(reason.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(reason.actionTitle, action: openSettings)
                .controlSize(.small)
                .padding(.top, 2)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(reason.accessibilityLabel)
    }
}
