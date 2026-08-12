import Foundation
import InstantTranslationCore

public struct KeyboardShortcut: Codable, Equatable, Sendable {
    public let keyCode: UInt32
    public let carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }
}

public struct AppPreferences: Codable, Equatable, Sendable {
    public var launchAtLogin = false
    public var globalShortcut: KeyboardShortcut?
    public var translateClipboardOnOpen = false
    public var llmBaseURL = ""
    public var llmModel = ""
    public var generalPrompt = DefaultPrompts.general
    public var technologyAndRnDPrompt = DefaultPrompts.technologyAndRnD
    public var defaultPromptPresetID = PromptPresetID.technologyAndRnD

    public init() {}
}

public protocol PreferencesStoring: Sendable {
    func load() async -> AppPreferences
    func save(_ preferences: AppPreferences) async throws
}

public actor UserDefaultsPreferencesStore: PreferencesStoring {
    private let defaults: UserDefaults
    private let key = "appPreferences"

    // 密钥不能写入 UserDefaults；这里只保存可同步、可恢复的非敏感应用偏好。
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppPreferences {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(AppPreferences.self, from: data)
        else {
            return AppPreferences()
        }
        return value
    }

    public func save(_ preferences: AppPreferences) throws {
        defaults.set(try JSONEncoder().encode(preferences), forKey: key)
    }
}
