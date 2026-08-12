import Foundation
import InstantTranslationCore
import XCTest
@testable import InstantTranslationInfrastructure

final class StorageTests: XCTestCase {
    func testDefaultPreferencesAreOptInAndTechnologyFocused() async throws {
        let suite = "InstantTranslationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        let store = UserDefaultsPreferencesStore(defaults: defaults)
        let preferences = await store.load()

        XCTAssertFalse(preferences.launchAtLogin)
        XCTAssertNil(preferences.globalShortcut)
        XCTAssertFalse(preferences.translateClipboardOnOpen)
        XCTAssertEqual(preferences.defaultPromptPresetID, .technologyAndRnD)
    }

    func testKeychainRoundTripUsesApplicationService() throws {
        let account = "test.\(UUID().uuidString)"
        let store = KeychainCredentialStore(service: "com.instanttranslation.macos.credentials.tests")
        defer { try? store.delete(.custom(account)) }

        try store.write("secret-value", for: .custom(account))

        XCTAssertEqual(try store.read(.custom(account)), "secret-value")
    }

    func testPreferencesPersistenceDoesNotContainCredentialValue() async throws {
        let suite = "InstantTranslationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        let store = UserDefaultsPreferencesStore(defaults: defaults)
        try await store.save(AppPreferences())

        let persistedDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let persistedData = try XCTUnwrap(persistedDefaults.data(forKey: "appPreferences"))
        XCTAssertFalse(String(decoding: persistedData, as: UTF8.self).contains("secret-value"))
        XCTAssertFalse(persistedDefaults.dictionaryRepresentation().values.contains { "\($0)".contains("secret-value") })
    }
}
