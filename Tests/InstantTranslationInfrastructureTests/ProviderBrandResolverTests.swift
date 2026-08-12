import XCTest
@testable import InstantTranslationInfrastructure

final class ProviderBrandResolverTests: XCTestCase {
    func testResolvesKnownHostsAndUsesGenericFallback() {
        let cases: [(baseURL: String, brand: ProviderBrand)] = [
            ("https://api.openai.com/v1", .openAI),
            ("https://gateway.openai.com/v1", .openAI),
            ("https://api.deepseek.com/v1", .deepSeek),
            ("https://openrouter.ai/api/v1", .openRouter),
            ("http://localhost:11434/v1", .genericAI),
            ("https://not-openai.com/v1", .genericAI),
            ("not a URL", .genericAI),
        ]

        for testCase in cases {
            XCTAssertEqual(
                ProviderBrandResolver.resolve(baseURL: testCase.baseURL),
                testCase.brand
            )
        }
    }
}
