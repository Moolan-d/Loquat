import XCTest
@testable import InstantTranslationCore

final class InputAndDirectionTests: XCTestCase {
    func testManualInputTrimsEdgesAndPreservesInternalWhitespace() async throws {
        let source = ManualInputSource(rawValue: "  just-in-time  compilation  ")

        let text = try await source.read()

        XCTAssertEqual(text?.value, "just-in-time  compilation")
        XCTAssertEqual(text?.sourceID, .manual)
    }

    func testClipboardIgnoresEmptyTranslatesFiveHundredAndConfirmsFiveHundredOne() {
        let policy = ClipboardTextPolicy(automaticCharacterLimit: 500)

        XCTAssertEqual(policy.evaluate(nil), .ignore)
        XCTAssertEqual(policy.evaluate("  \n  "), .ignore)
        XCTAssertEqual(policy.evaluate(String(repeating: "a", count: 500)).shouldSubmit, true)
        XCTAssertEqual(policy.evaluate(String(repeating: "a", count: 501)).shouldSubmit, false)
    }

    func testDirectionUsesHanContentOtherwiseEnglish() {
        let resolver = DirectionResolver()

        XCTAssertEqual(resolver.resolve("即时编译").source, .simplifiedChinese)
        XCTAssertEqual(resolver.resolve("即时编译").target, .english)
        XCTAssertEqual(resolver.resolve("JIT compilation").source, .english)
        XCTAssertEqual(resolver.resolve("JIT compilation").target, .simplifiedChinese)
    }
}
