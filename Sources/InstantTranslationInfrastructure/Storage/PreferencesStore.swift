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
    public var translateClipboardOnShortcut = false
    public var googleProviderEnabled = true
    public var llmProviderEnabled = true
    public var googleCredentialConfigured = false
    public var llmCredentialConfigured = false
    public var llmBaseURL = ""
    public var llmModel = ""
    public var generalPrompt = DefaultPrompts.general
    public var technologyAndRnDPrompt = DefaultPrompts.technologyAndRnD
    public var defaultPromptPresetID = PromptPresetID.technologyAndRnD

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case globalShortcut
        case translateClipboardOnShortcut
        case googleProviderEnabled
        case llmProviderEnabled
        case googleCredentialConfigured = "googleCredentialV3Configured"
        case llmCredentialConfigured = "llmCredentialV3Configured"
        case llmBaseURL
        case llmModel
        case generalPrompt
        case technologyAndRnDPrompt
        case defaultPromptPresetID
    }

    // 合成的 Codable 会把缺失键当成错误，于是新增一个字段就让旧快照整体解码失败并被重置为默认值。
    // 逐字段回退到默认值后，旧版本写入的偏好在字段演进后仍然保留。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppPreferences()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? container.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        launchAtLogin = value(.launchAtLogin, defaults.launchAtLogin)
        globalShortcut = try? container.decodeIfPresent(
            KeyboardShortcut.self,
            forKey: .globalShortcut
        )
        translateClipboardOnShortcut = value(
            .translateClipboardOnShortcut,
            defaults.translateClipboardOnShortcut
        )
        googleProviderEnabled = value(.googleProviderEnabled, defaults.googleProviderEnabled)
        llmProviderEnabled = value(.llmProviderEnabled, defaults.llmProviderEnabled)
        googleCredentialConfigured = value(
            .googleCredentialConfigured,
            defaults.googleCredentialConfigured
        )
        llmCredentialConfigured = value(
            .llmCredentialConfigured,
            defaults.llmCredentialConfigured
        )
        llmBaseURL = value(.llmBaseURL, defaults.llmBaseURL)
        llmModel = value(.llmModel, defaults.llmModel)
        generalPrompt = value(.generalPrompt, defaults.generalPrompt)
        technologyAndRnDPrompt = value(
            .technologyAndRnDPrompt,
            defaults.technologyAndRnDPrompt
        )
        defaultPromptPresetID = value(
            .defaultPromptPresetID,
            defaults.defaultPromptPresetID
        )
        // 剪贴板读取只在快捷键唤起时发生；磁盘上「无快捷键但开关为真」的历史数据在此规范化为假。
        if globalShortcut == nil {
            translateClipboardOnShortcut = false
        }
    }
}

extension AppPreferences {
    /// 分组开关是持久化偏好，窗口与设置界面都从这里读取，避免两处各自推导出不同结论。
    public var enabledProviderIDs: Set<ProviderID> {
        var enabled: Set<ProviderID> = []
        if googleProviderEnabled {
            enabled.insert(.google)
        }
        if llmProviderEnabled {
            enabled.insert(.llm)
        }
        return enabled
    }
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
