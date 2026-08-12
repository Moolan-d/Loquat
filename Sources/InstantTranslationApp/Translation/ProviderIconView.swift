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
final class BundledProviderLogoLoader {
    static let shared = BundledProviderLogoLoader(bundle: .module)

    private let bundle: Bundle
    private var cachedLogos: [String: BundledProviderLogo] = [:]
    private var missingBrands: Set<String> = []

    init(bundle: Bundle) {
        self.bundle = bundle
    }

    func logo(for brand: ProviderBrand) -> BundledProviderLogo? {
        if let cached = cachedLogos[brand.rawValue] {
            return cached
        }
        guard !missingBrands.contains(brand.rawValue) else { return nil }

        guard let resource = Self.resource(for: brand),
              let resourceURL = bundle.url(
                  forResource: resource.filename,
                  withExtension: "svg",
                  subdirectory: "ProviderLogos.xcassets/\(resource.imageset).imageset"
              ),
              let image = NSImage(contentsOf: resourceURL),
              image.size.width > 0,
              image.size.height > 0
        else {
            missingBrands.insert(brand.rawValue)
            return nil
        }

        image.isTemplate = true
        let logo = BundledProviderLogo(image: image, resourceURL: resourceURL)
        cachedLogos[brand.rawValue] = logo
        return logo
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
            if let logo = BundledProviderLogoLoader.shared.logo(for: brand) {
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
