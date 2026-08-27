import Foundation
import InstantTranslationCore
import Security
import XCTest
@testable import InstantTranslationInfrastructure

final class StorageTests: XCTestCase {
    private static let keychainService = "com.instanttranslation.macos.credentials.tests"
    private static let keychainAccountPrefix = "InstantTranslationTests."

    override func setUpWithError() throws {
        try super.setUpWithError()
        try Self.removeTestCredentials()
    }

    override func tearDownWithError() throws {
        try Self.removeTestCredentials()
        try super.tearDownWithError()
    }

    func testDefaultPreferencesAreOptInAndTechnologyFocused() async throws {
        let suite = "InstantTranslationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        let store = UserDefaultsPreferencesStore(defaults: defaults)
        let preferences = await store.load()

        XCTAssertFalse(preferences.launchAtLogin)
        XCTAssertNil(preferences.globalShortcut)
        XCTAssertFalse(preferences.translateClipboardOnShortcut)
        XCTAssertEqual(preferences.defaultPromptPresetID, .technologyAndRnD)
        XCTAssertFalse(preferences.googleCredentialConfigured)
        XCTAssertFalse(preferences.llmCredentialConfigured)
    }

    func testLegacyPreferencesSnapshotKeepsValuesWhenNewFieldsAreAdded() async throws {
        let suite = "InstantTranslationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        // 旧版本写入的快照没有 provider 开关键；解码必须逐字段回退而不是整体重置。
        // 旧键 translateClipboardOnOpen 随改名被丢弃，新字段回退到默认 false（接受重置）。
        let legacy = """
        {
          "launchAtLogin": true,
          "translateClipboardOnOpen": true,
          "llmBaseURL": "https://api.openai.com/v1",
          "llmModel": "gpt-4o-mini",
          "generalPrompt": "legacy general",
          "technologyAndRnDPrompt": "legacy technology",
          "defaultPromptPresetID": "general"
        }
        """
        defaults.set(Data(legacy.utf8), forKey: "appPreferences")

        let preferences = await UserDefaultsPreferencesStore(defaults: defaults).load()

        XCTAssertTrue(preferences.launchAtLogin)
        XCTAssertFalse(preferences.translateClipboardOnShortcut)
        XCTAssertEqual(preferences.llmBaseURL, "https://api.openai.com/v1")
        XCTAssertEqual(preferences.llmModel, "gpt-4o-mini")
        XCTAssertEqual(preferences.generalPrompt, "legacy general")
        XCTAssertEqual(preferences.technologyAndRnDPrompt, "legacy technology")
        XCTAssertEqual(preferences.defaultPromptPresetID, .general)
        XCTAssertTrue(preferences.googleProviderEnabled)
        XCTAssertTrue(preferences.llmProviderEnabled)
        XCTAssertFalse(preferences.googleCredentialConfigured)
        XCTAssertFalse(preferences.llmCredentialConfigured)
    }

    func testCredentialPresenceHintsSurviveSaveAndReloadWithoutSecretValues() async throws {
        let suite = "InstantTranslationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        var preferences = AppPreferences()
        preferences.googleCredentialConfigured = true
        preferences.llmCredentialConfigured = true
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        try await store.save(preferences)

        let reloaded = await store.load()
        XCTAssertTrue(reloaded.googleCredentialConfigured)
        XCTAssertTrue(reloaded.llmCredentialConfigured)

        let persistedDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let persisted = try XCTUnwrap(persistedDefaults.data(forKey: "appPreferences"))
        let text = String(decoding: persisted, as: UTF8.self)
        XCTAssertFalse(text.contains("api-key"))
        XCTAssertFalse(text.contains("secret"))
        XCTAssertTrue(text.contains("\"googleCredentialV3Configured\":true"))
        XCTAssertTrue(text.contains("\"llmCredentialV3Configured\":true"))
        XCTAssertFalse(text.contains("\"googleCredentialConfigured\""))
        XCTAssertFalse(text.contains("\"llmCredentialConfigured\""))
    }

    func testPreV3PresenceHintsResetWithoutDiscardingOtherPreferences() throws {
        let legacy = """
        {
          "launchAtLogin": true,
          "googleCredentialConfigured": true,
          "llmCredentialConfigured": true,
          "llmBaseURL": "https://api.openai.com/v1"
        }
        """

        let preferences = try JSONDecoder().decode(
            AppPreferences.self,
            from: Data(legacy.utf8)
        )

        XCTAssertTrue(preferences.launchAtLogin)
        XCTAssertEqual(preferences.llmBaseURL, "https://api.openai.com/v1")
        XCTAssertFalse(preferences.googleCredentialConfigured)
        XCTAssertFalse(preferences.llmCredentialConfigured)
    }

    func testProviderVisibilitySurvivesSaveAndReload() async throws {
        let suite = "InstantTranslationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        var preferences = AppPreferences()
        preferences.googleProviderEnabled = false
        preferences.llmBaseURL = "https://api.openai.com/v1"
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        try await store.save(preferences)

        // load 每次都从 UserDefaults 重新解码，因此这里验证的是完整的编解码往返。
        let reloaded = await store.load()

        XCTAssertFalse(reloaded.googleProviderEnabled)
        XCTAssertTrue(reloaded.llmProviderEnabled)
        XCTAssertEqual(reloaded.llmBaseURL, "https://api.openai.com/v1")
    }

    func testClipboardOnShortcutSurvivesSaveAndReloadWithShortcut() async throws {
        let suite = "InstantTranslationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        var preferences = AppPreferences()
        preferences.globalShortcut = KeyboardShortcut(keyCode: 1, carbonModifiers: 512)
        preferences.translateClipboardOnShortcut = true
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        try await store.save(preferences)

        let reloaded = await store.load()
        XCTAssertTrue(reloaded.translateClipboardOnShortcut)
    }

    func testClipboardOnShortcutIsClearedWhenNoShortcutOnLoad() async throws {
        let suite = "InstantTranslationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        // 磁盘上「无快捷键但剪贴板开关为真」违反不变量，加载时规范化为假。
        let snapshot = """
        {
          "translateClipboardOnShortcut": true,
          "llmBaseURL": "https://api.openai.com/v1",
          "llmModel": "gpt-4o-mini"
        }
        """
        defaults.set(Data(snapshot.utf8), forKey: "appPreferences")

        let preferences = await UserDefaultsPreferencesStore(defaults: defaults).load()
        XCTAssertFalse(preferences.translateClipboardOnShortcut)
    }

    func testKeychainRoundTripUsesApplicationService() throws {
        let account = Self.makeTestAccount()
        let client = TestSecItemClient()
        let store = KeychainCredentialStore(
            service: Self.keychainService,
            client: client
        )

        try store.write("secret-value", for: .custom(account))

        XCTAssertEqual(try store.read(.custom(account)), "secret-value")
    }

    func testConcurrentKeychainWritesDoNotThrow() async throws {
        let account = Self.makeTestAccount()
        let client = TestSecItemClient(missingUpdateBarrierCount: 2)
        let store = KeychainCredentialStore(
            service: Self.keychainService,
            client: client
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try store.write("first-value", for: .custom(account))
            }
            group.addTask {
                try store.write("second-value", for: .custom(account))
            }
            try await group.waitForAll()
        }

        let value = try XCTUnwrap(try store.read(.custom(account)))
        XCTAssertTrue(["first-value", "second-value"].contains(value))
    }

    func testInvalidKeychainDataThrowsInsteadOfReturningMissingCredential() throws {
        let account = Self.makeTestAccount()
        let client = TestSecItemClient()
        client.insertRawData(
            Data([0xFF]),
            service: Self.keychainService,
            account: account
        )
        let store = KeychainCredentialStore(
            service: Self.keychainService,
            client: client
        )

        XCTAssertThrowsError(try store.read(.custom(account))) { error in
            XCTAssertEqual(error as? KeychainError, .invalidData)
        }
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

    private static func makeTestAccount() -> String {
        "\(keychainAccountPrefix)\(UUID().uuidString)"
    }

    private static func removeTestCredentials() throws {
        let accounts = try testCredentialAccounts()
        for account in accounts {
            let status = SecItemDelete(
                keychainQuery(account: account) as CFDictionary
            )
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw TestKeychainError.status(status)
            }
        }
    }

    private static func testCredentialAccounts() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw TestKeychainError.status(status)
        }

        let attributes: [[String: Any]]
        if let items = item as? [[String: Any]] {
            attributes = items
        } else if let singleItem = item as? [String: Any] {
            attributes = [singleItem]
        } else {
            throw TestKeychainError.invalidAttributes
        }

        return attributes.compactMap { attributes in
            guard let account = attributes[kSecAttrAccount as String] as? String,
                  account.hasPrefix(keychainAccountPrefix)
            else {
                return nil
            }
            return account
        }
    }

    private static func keychainQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
    }
}

private enum TestKeychainError: Error {
    case invalidAttributes
    case status(OSStatus)
}

private final class TestSecItemClient: KeychainSecItemClient, @unchecked Sendable {
    private struct ItemKey: Hashable {
        let service: String
        let account: String
    }

    private let condition = NSCondition()
    private let missingUpdateBarrierCount: Int
    private var missingUpdateArrivals = 0
    private var releasedMissingUpdateBarrier = false
    private var items: [ItemKey: [String: Any]] = [:]

    init(missingUpdateBarrierCount: Int = 0) {
        self.missingUpdateBarrierCount = missingUpdateBarrierCount
    }

    func copyMatching(_ query: [String: Any]) -> KeychainSecItemResult {
        condition.lock()
        defer { condition.unlock() }

        guard let key = itemKey(from: query) else {
            return KeychainSecItemResult(status: errSecParam, item: nil)
        }
        guard let attributes = items[key] else {
            return KeychainSecItemResult(status: errSecItemNotFound, item: nil)
        }
        if query[kSecReturnData as String] as? Bool == true {
            return KeychainSecItemResult(
                status: errSecSuccess,
                item: attributes[kSecValueData as String]
            )
        }
        if query[kSecReturnAttributes as String] as? Bool == true {
            return KeychainSecItemResult(status: errSecSuccess, item: attributes)
        }
        return KeychainSecItemResult(status: errSecSuccess, item: nil)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        condition.lock()
        defer { condition.unlock() }

        guard let key = itemKey(from: query) else {
            return errSecParam
        }
        guard var item = items[key] else {
            guard waitForMissingUpdateBarrierIfNeeded() else {
                return errSecInternalComponent
            }
            return errSecItemNotFound
        }
        attributes.forEach { item[$0.key] = $0.value }
        items[key] = item
        return errSecSuccess
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        condition.lock()
        defer { condition.unlock() }

        guard let key = itemKey(from: attributes) else {
            return errSecParam
        }
        guard items[key] == nil else {
            return errSecDuplicateItem
        }
        items[key] = attributes
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        condition.lock()
        defer { condition.unlock() }

        guard let key = itemKey(from: query) else {
            return errSecParam
        }
        return items.removeValue(forKey: key) == nil ? errSecItemNotFound : errSecSuccess
    }

    func insertRawData(
        _ data: Data,
        service: String,
        account: String
    ) {
        condition.lock()
        defer { condition.unlock() }

        let key = ItemKey(service: service, account: account)
        items[key] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
    }

    private func itemKey(from attributes: [String: Any]) -> ItemKey? {
        guard let service = attributes[kSecAttrService as String] as? String,
              let account = attributes[kSecAttrAccount as String] as? String
        else {
            return nil
        }
        return ItemKey(service: service, account: account)
    }

    private func waitForMissingUpdateBarrierIfNeeded() -> Bool {
        guard missingUpdateBarrierCount > 0, !releasedMissingUpdateBarrier else {
            return true
        }

        missingUpdateArrivals += 1
        if missingUpdateArrivals == missingUpdateBarrierCount {
            releasedMissingUpdateBarrier = true
            condition.broadcast()
            return true
        }
        let deadline = Date().addingTimeInterval(5)
        while !releasedMissingUpdateBarrier {
            guard condition.wait(until: deadline) else {
                return false
            }
        }
        return true
    }
}
