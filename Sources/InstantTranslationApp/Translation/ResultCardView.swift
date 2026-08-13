import SwiftUI
import InstantTranslationCore
import InstantTranslationFeature
import InstantTranslationInfrastructure

enum TranslationPresentationStyle {
    static let copyFailureColor = NSColor.systemRed
}

@MainActor
public struct ResultCardView: View {
    private let providerID: ProviderID
    private let state: ProviderCardState
    private let llmBrand: ProviderBrand
    private let isConfigured: Bool
    @Bindable private var copyController: CopyController
    private let retry: () -> Void
    private let openSettings: @MainActor () -> Void

    public init(
        providerID: ProviderID,
        state: ProviderCardState,
        llmBrand: ProviderBrand,
        isConfigured: Bool = true,
        copyController: CopyController,
        retry: @escaping () -> Void,
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
        self.copyController = copyController
        self.retry = retry
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
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ProviderIconView(providerID: providerID, llmBrand: llmBrand)
                        Spacer()
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
                    Text(result.primaryText)
                        .textSelection(.enabled)
                    if let rationale = result.rationale, !rationale.isEmpty {
                        Text(rationale)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
