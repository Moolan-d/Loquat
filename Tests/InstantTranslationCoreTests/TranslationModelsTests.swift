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
}
