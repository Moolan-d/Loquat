import XCTest
@testable import InstantTranslationInfrastructure

final class LLMDefaultModelTests: XCTestCase {
    func testFallsBackToTheFreeRouterOnlyForOpenRouterHosts() {
        let cases: [(baseURL: String, model: String?)] = [
            ("https://openrouter.ai/api/v1", "openrouter/free"),
            ("https://openrouter.ai/api/v1/", "openrouter/free"),
            ("https://gateway.openrouter.ai/api/v1", "openrouter/free"),
            ("https://api.openai.com/v1", nil),
            ("https://api.deepseek.com/v1", nil),
            ("http://localhost:11434/v1", nil),
            // openrouter.ai.evil.example 不是 OpenRouter：后缀匹配必须带点号边界。
            ("https://openrouter.ai.evil.example/v1", nil),
            ("", nil),
            ("not a URL", nil),
        ]

        for testCase in cases {
            XCTAssertEqual(
                LLMDefaultModel.resolve(baseURL: testCase.baseURL),
                testCase.model,
                testCase.baseURL
            )
        }
    }
}
