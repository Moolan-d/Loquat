import SwiftUI
import InstantTranslationCore
import InstantTranslationFeature
import InstantTranslationInfrastructure

@MainActor
public struct ResultCardView: View {
    private let providerID: ProviderID
    private let state: ProviderCardState
    private let llmBrand: ProviderBrand
    @Bindable private var copyController: CopyController
    private let retry: () -> Void

    public init(
        providerID: ProviderID,
        state: ProviderCardState,
        llmBrand: ProviderBrand,
        copyController: CopyController,
        retry: @escaping () -> Void
    ) {
        self.providerID = providerID
        self.state = state
        self.llmBrand = llmBrand
        self.copyController = copyController
        self.retry = retry
    }

    public var body: some View {
        Group {
            switch state {
            case .idle:
                Color.clear.frame(height: 52)
            case .loading:
                HStack {
                    ProviderIconView(providerID: providerID, llmBrand: llmBrand)
                    ProgressView().controlSize(.small)
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
                            .foregroundStyle(.red)
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
