import AppKit
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

struct BundledProviderLogo {
    let image: NSImage
    let resourceURL: URL
}

@MainActor
enum BundledProviderLogoLoader {
    static func logo(
        for brand: ProviderBrand,
        bundle: Bundle = .module
    ) -> BundledProviderLogo? {
        guard let resource = resource(for: brand),
              let resourceURL = bundle.url(
                  forResource: resource.filename,
                  withExtension: "svg",
                  subdirectory: "ProviderLogos.xcassets/\(resource.imageset).imageset"
              ),
              let image = NSImage(contentsOf: resourceURL),
              image.size.width > 0,
              image.size.height > 0
        else {
            return nil
        }

        image.isTemplate = true
        return BundledProviderLogo(image: image, resourceURL: resourceURL)
    }

    private static func resource(
        for brand: ProviderBrand
    ) -> (imageset: String, filename: String)? {
        switch brand {
        case .googleTranslate:
            ("GoogleTranslate", "googletranslate")
        case .openAI:
            ("OpenAI", "openai")
        case .deepSeek:
            ("DeepSeek", "deepseek")
        case .openRouter:
            ("OpenRouter", "openrouter")
        case .genericAI:
            nil
        }
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
            if let logo = BundledProviderLogoLoader.logo(for: brand) {
                Image(nsImage: logo.image)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.primary)
            } else {
                Image(systemName: "sparkles")
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}
