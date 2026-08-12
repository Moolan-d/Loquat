import Observation
import SwiftUI
import InstantTranslationCore
import InstantTranslationInfrastructure

@MainActor
@Observable
public final class ProviderAppearance {
    public var llmBrand: ProviderBrand

    public init(llmBrand: ProviderBrand) {
        self.llmBrand = llmBrand
    }
}

public struct ProviderIconView: View {
    public let providerID: ProviderID
    public let llmBrand: ProviderBrand

    public init(providerID: ProviderID, llmBrand: ProviderBrand) {
        self.providerID = providerID
        self.llmBrand = llmBrand
    }

    public var body: some View {
        let brand = providerID == .google ? ProviderBrand.googleTranslate : llmBrand

        Group {
            if brand == .genericAI {
                Image(systemName: "sparkles")
            } else {
                Image(assetName(for: brand), bundle: .module)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }

    private func assetName(for brand: ProviderBrand) -> String {
        switch brand {
        case .googleTranslate:
            "GoogleTranslate"
        case .openAI:
            "OpenAI"
        case .deepSeek:
            "DeepSeek"
        case .openRouter:
            "OpenRouter"
        case .genericAI:
            ""
        }
    }
}
