import XCTest
@testable import InstantTranslationCore

final class TranslationModelsTests: XCTestCase {
    func testInitialCatalogContainsOnlyChineseAndEnglish() {
        XCTAssertEqual(LanguageCatalog.initial.languages.map(\.id), [.simplifiedChinese, .english])
        XCTAssertEqual(LanguageID.simplifiedChinese.googleCode, "zh-CN")
        XCTAssertEqual(LanguageID.english.googleCode, "en")
    }

    func testResultCarriesFuturePronunciationAndSpeechFieldsWithoutAudioObjects() {
        let pronunciation = Pronunciation(
            scheme: PronunciationScheme("ipa"),
            text: "/ˈkɒmpaɪlə/",
            language: .english,
            source: .llm
        )
        let result = TranslationResult(
            providerID: .llm,
            requestID: UUID(),
            primaryText: "compiler",
            rationale: "A standard software-engineering term.",
            sourceLanguage: .simplifiedChinese,
            targetLanguage: .english,
            pronunciations: [pronunciation],
            speakableText: "compiler",
            duration: .milliseconds(20)
        )
        XCTAssertEqual(result.pronunciations, [pronunciation])
        XCTAssertEqual(result.speakableText, "compiler")
    }

    func testWordSenseCarriesOptionalBilingualExample() {
        let sense = WordSense(
            label: "日常",
            meaning: "自尊心、面子",
            example: "His ego was bruised.",
            exampleTranslation: "他的自尊心受挫了。"
        )

        // 例句与译文分开存：原文要斜体、译文不要，混成一个字符串就没法分开排版。
        XCTAssertEqual(sense.example, "His ego was bruised.")
        XCTAssertEqual(sense.exampleTranslation, "他的自尊心受挫了。")
    }

    func testContextExpansionIsBoundToOriginalRequest() {
        let requestID = UUID()
        let expansion = ContextExpansionResult(
            requestID: requestID,
            senses: [.init(label: "网络", meaning: "过度自我关注", example: nil)]
        )

        // 补充语境是第二次请求的产物，迟到的那份得能认出自己属于哪一轮。
        XCTAssertEqual(expansion.requestID, requestID)
        XCTAssertEqual(expansion.senses.count, 1)
    }
}
