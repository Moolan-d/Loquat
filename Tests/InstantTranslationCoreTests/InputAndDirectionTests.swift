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

    func testSenseExpansionSeparatesLookupFromTranslatingASentence() {
        let policy = SenseExpansionPolicy()

        // 查词才要义项；一旦成句就是在翻译，不该再往请求里塞词典指令。
        XCTAssertTrue(policy.shouldExpand("beef"))
        XCTAssertTrue(policy.shouldExpand("spill the tea"))
        XCTAssertFalse(policy.shouldExpand("have a beef with someone"))
    }

    func testSenseExpansionCountsCharactersWheneverHanIsPresent() {
        let policy = SenseExpansionPolicy()

        // 中文没有空格，按词数整段都算一个词，闸门会全线失守，所以含汉字一律改数字数。
        XCTAssertTrue(policy.shouldExpand("内卷"))
        XCTAssertFalse(policy.shouldExpand("这也太city了吧"))
        // 中英混排同样走字数：按词数 "内卷 subculture" 只有两个词，会被误判成查词。
        XCTAssertTrue(policy.shouldExpand("内卷 文化"))
        XCTAssertFalse(policy.shouldExpand("内卷 subculture"))
    }

    func testSenseExpansionIgnoresWhitespaceAndRefusesEmptyInput() {
        let policy = SenseExpansionPolicy()

        XCTAssertTrue(policy.shouldExpand("  spill   the   tea  "))
        // 空输入根本不会发出请求，这里守住的是策略自己不把 0 当成“短”而返回真。
        XCTAssertFalse(policy.shouldExpand(""))
        XCTAssertFalse(policy.shouldExpand("   \n "))
    }

    func testSenseExpansionBoundariesAreInclusiveAtTheConfiguredLimits() {
        let policy = SenseExpansionPolicy(maximumWordCount: 3, maximumCharacterCount: 6)

        XCTAssertTrue(policy.shouldExpand("one two three"))
        XCTAssertFalse(policy.shouldExpand("one two three four"))
        XCTAssertTrue(policy.shouldExpand("六个汉字整好"))
        XCTAssertFalse(policy.shouldExpand("七个汉字就超了"))
    }
}
