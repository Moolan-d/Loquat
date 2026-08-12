import Foundation
import Observation
import InstantTranslationCore
import InstantTranslationFeature
import InstantTranslationInfrastructure

public enum ConnectionTestState: Equatable, Sendable {
    case idle
    case testing
    case success
    case failure(TranslationProviderError)
}

public protocol ProviderConnectionTesting: Sendable {
    func testGoogle(apiKey: String) async -> ConnectionTestState
    func testLLM(configuration: LLMProviderConfiguration) async -> ConnectionTestState
}

public struct ProviderConnectionTester: ProviderConnectionTesting {
    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport) {
        self.transport = transport
    }

    public func testGoogle(apiKey: String) async -> ConnectionTestState {
        await test(GoogleTranslationProvider(transport: transport) { apiKey })
    }

    public func testLLM(configuration: LLMProviderConfiguration) async -> ConnectionTestState {
        await test(OpenAICompatibleProvider(transport: transport) { _ in configuration })
    }

    private func test(_ provider: any TranslationProvider) async -> ConnectionTestState {
        let request = TranslationRequest(
            id: UUID(),
            text: "test",
            inputSource: .manual,
            sourceLanguage: .english,
            targetLanguage: .simplifiedChinese,
            directionOrigin: .manual,
            promptPresetID: .general
        )
        do {
            _ = try await provider.translate(request)
            return .success
        } catch let error as TranslationProviderError {
            return .failure(error)
        } catch {
            return .failure(.invalidResponse)
        }
    }
}

public enum SettingsSaveState: Equatable, Sendable {
    case idle
    case saving
    case saved
    case failed
    case needsAttention
}

public enum SettingsSaveError: Error, Equatable, Sendable {
    case invalidLLMConfiguration
    case invalidPrompt
    case insecureEndpoint
    case persistenceFailed
    case rollbackIncomplete
}

extension SettingsSaveError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidLLMConfiguration:
            "Complete the LLM Base URL, API key, and model, or clear all three."
        case .invalidPrompt:
            "Prompts cannot be empty."
        case .insecureEndpoint:
            "Use HTTPS, or HTTP only on this Mac."
        case .persistenceFailed:
            "Settings could not be saved. Try again."
        case .rollbackIncomplete:
            "Settings could not be restored completely. Review them and try again."
        }
    }
}

@MainActor
@Observable
public final class SettingsViewModel {
    public var launchAtLogin: Bool
    public var globalShortcut: KeyboardShortcut?
    public var translateClipboardOnOpen: Bool
    public var llmBaseURL: String
    public var llmModel: String
    public var generalPrompt: String
    public var technologyAndRnDPrompt: String
    public var defaultPromptPresetID: PromptPresetID
    public var googleAPIKey: String
    public var llmAPIKey: String
    public private(set) var googleConnectionState = ConnectionTestState.idle
    public private(set) var llmConnectionState = ConnectionTestState.idle
    public private(set) var saveState = SettingsSaveState.idle
    public private(set) var saveError: String?

    private let preferencesStore: any PreferencesStoring
    private let credentialStore: any CredentialStoring
    private let launchController: LaunchAtLoginControlling
    private let shortcutRegistrar: GlobalShortcutRegistering
    private let shortcutAction: @MainActor () -> Void
    private let connectionTester: any ProviderConnectionTesting
    private let providerAppearance: ProviderAppearance
    private weak var session: TranslationSession?
    private var googleTestGeneration = 0
    private var llmTestGeneration = 0

    public static func make(
        preferencesStore: any PreferencesStoring,
        credentialStore: any CredentialStoring,
        launchAtLogin: LaunchAtLoginControlling,
        shortcutRegistrar: GlobalShortcutRegistering,
        shortcutAction: @escaping @MainActor () -> Void,
        connectionTester: any ProviderConnectionTesting,
        providerAppearance: ProviderAppearance,
        session: TranslationSession?
    ) async -> SettingsViewModel {
        let preferences = await preferencesStore.load()
        let googleAPIKey = (try? credentialStore.read(.googleAPIKey)) ?? ""
        let llmAPIKey = (try? credentialStore.read(.llmAPIKey)) ?? ""
        return SettingsViewModel(
            preferences: preferences,
            googleAPIKey: googleAPIKey,
            llmAPIKey: llmAPIKey,
            actualLaunchAtLogin: launchAtLogin.isEnabled,
            preferencesStore: preferencesStore,
            credentialStore: credentialStore,
            launchController: launchAtLogin,
            shortcutRegistrar: shortcutRegistrar,
            shortcutAction: shortcutAction,
            connectionTester: connectionTester,
            providerAppearance: providerAppearance,
            session: session
        )
    }

    private init(
        preferences: AppPreferences,
        googleAPIKey: String,
        llmAPIKey: String,
        actualLaunchAtLogin: Bool,
        preferencesStore: any PreferencesStoring,
        credentialStore: any CredentialStoring,
        launchController: LaunchAtLoginControlling,
        shortcutRegistrar: GlobalShortcutRegistering,
        shortcutAction: @escaping @MainActor () -> Void,
        connectionTester: any ProviderConnectionTesting,
        providerAppearance: ProviderAppearance,
        session: TranslationSession?
    ) {
        launchAtLogin = actualLaunchAtLogin
        globalShortcut = preferences.globalShortcut
        translateClipboardOnOpen = preferences.translateClipboardOnOpen
        llmBaseURL = preferences.llmBaseURL
        llmModel = preferences.llmModel
        generalPrompt = preferences.generalPrompt
        technologyAndRnDPrompt = preferences.technologyAndRnDPrompt
        defaultPromptPresetID = preferences.defaultPromptPresetID
        self.googleAPIKey = googleAPIKey
        self.llmAPIKey = llmAPIKey
        self.preferencesStore = preferencesStore
        self.credentialStore = credentialStore
        self.launchController = launchController
        self.shortcutRegistrar = shortcutRegistrar
        self.shortcutAction = shortcutAction
        self.connectionTester = connectionTester
        self.providerAppearance = providerAppearance
        self.session = session
    }

    public func save() async throws {
        saveState = .saving
        saveError = nil

        let proposed: ProposedSettings
        do {
            proposed = try validatedSettings()
        } catch let error as SettingsSaveError {
            recordFailure(error, rollbackIncomplete: false)
            throw error
        } catch {
            let publicError = SettingsSaveError.persistenceFailed
            recordFailure(publicError, rollbackIncomplete: false)
            throw publicError
        }

        let oldPreferences = await preferencesStore.load()
        let oldGoogleKey: String?
        let oldLLMKey: String?
        do {
            oldGoogleKey = try credentialStore.read(.googleAPIKey)
            oldLLMKey = try credentialStore.read(.llmAPIKey)
        } catch {
            let publicError = SettingsSaveError.persistenceFailed
            recordFailure(publicError, rollbackIncomplete: false)
            throw publicError
        }
        let oldLaunch = launchController.isEnabled

        var shortcutAttempted = false
        var launchAttempted = false
        var googleCredentialAttempted = false
        var llmCredentialAttempted = false
        var preferencesAttempted = false

        do {
            // 快捷键与登录项先变更，偏好最后提交；失败时使用旧快照逆序补偿外部状态。
            shortcutAttempted = true
            try shortcutRegistrar.register(proposed.preferences.globalShortcut, action: shortcutAction)

            if launchController.isEnabled != proposed.preferences.launchAtLogin {
                launchAttempted = true
                try launchController.setEnabled(proposed.preferences.launchAtLogin)
            }

            googleCredentialAttempted = true
            try storeCredential(proposed.googleAPIKey, key: .googleAPIKey)
            llmCredentialAttempted = true
            try storeCredential(proposed.llmAPIKey, key: .llmAPIKey)

            preferencesAttempted = true
            try await preferencesStore.save(proposed.preferences)
        } catch {
            let rollbackFailed = await rollback(
                preferences: preferencesAttempted ? oldPreferences : nil,
                googleKey: googleCredentialAttempted ? .some(oldGoogleKey) : nil,
                llmKey: llmCredentialAttempted ? .some(oldLLMKey) : nil,
                launch: launchAttempted ? oldLaunch : nil,
                shortcut: oldPreferences.globalShortcut,
                restoreShortcut: shortcutAttempted
            )
            let publicError = rollbackFailed
                ? SettingsSaveError.rollbackIncomplete
                : SettingsSaveError.persistenceFailed
            recordFailure(publicError, rollbackIncomplete: rollbackFailed)
            throw publicError
        }

        applySuccessfulSave(proposed)
    }

    public func restoreGeneralPrompt() {
        generalPrompt = DefaultPrompts.general
    }

    public func restoreTechnologyAndRnDPrompt() {
        technologyAndRnDPrompt = DefaultPrompts.technologyAndRnD
    }

    public func testGoogleConnection() async {
        googleTestGeneration &+= 1
        let generation = googleTestGeneration
        let key = googleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            googleConnectionState = .failure(.unconfigured)
            return
        }
        googleConnectionState = .testing
        let result = await connectionTester.testGoogle(apiKey: key)
        // 用户可能连续点击；只有最新 generation 能发布状态，旧请求完成不能倒灌 UI。
        guard generation == googleTestGeneration else { return }
        googleConnectionState = result
    }

    public func testLLMConnection() async {
        llmTestGeneration &+= 1
        let generation = llmTestGeneration
        let configuration: LLMProviderConfiguration
        do {
            let proposed = try validatedSettings()
            guard !proposed.llmBaseURL.isEmpty else {
                llmConnectionState = .failure(.unconfigured)
                return
            }
            let prompt = proposed.preferences.defaultPromptPresetID == .general
                ? proposed.preferences.generalPrompt
                : proposed.preferences.technologyAndRnDPrompt
            configuration = LLMProviderConfiguration(
                baseURL: proposed.llmBaseURL,
                apiKey: proposed.llmAPIKey,
                model: proposed.preferences.llmModel,
                systemPrompt: prompt
            )
        } catch SettingsSaveError.insecureEndpoint {
            llmConnectionState = .failure(.insecureEndpoint)
            return
        } catch {
            llmConnectionState = .failure(.unconfigured)
            return
        }
        llmConnectionState = .testing
        let result = await connectionTester.testLLM(configuration: configuration)
        guard generation == llmTestGeneration else { return }
        llmConnectionState = result
    }

    private func validatedSettings() throws -> ProposedSettings {
        let baseURL = llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = llmModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let googleKey = googleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let llmKey = llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let general = generalPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let technology = technologyAndRnDPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !general.isEmpty, !technology.isEmpty else {
            throw SettingsSaveError.invalidPrompt
        }

        let llmFields = [baseURL, llmKey, model]
        let hasAnyLLMField = llmFields.contains { !$0.isEmpty }
        guard !hasAnyLLMField || llmFields.allSatisfy({ !$0.isEmpty }) else {
            throw SettingsSaveError.invalidLLMConfiguration
        }

        var normalizedBaseURL = ""
        if hasAnyLLMField {
            do {
                normalizedBaseURL = try EndpointPolicy.validatedAPIBaseURL(baseURL).absoluteString
            } catch {
                throw SettingsSaveError.insecureEndpoint
            }
        }

        var preferences = AppPreferences()
        preferences.launchAtLogin = launchAtLogin
        preferences.globalShortcut = globalShortcut
        preferences.translateClipboardOnOpen = translateClipboardOnOpen
        preferences.llmBaseURL = normalizedBaseURL
        preferences.llmModel = model
        preferences.generalPrompt = general
        preferences.technologyAndRnDPrompt = technology
        preferences.defaultPromptPresetID = defaultPromptPresetID
        return ProposedSettings(
            preferences: preferences,
            googleAPIKey: googleKey,
            llmAPIKey: llmKey,
            llmBaseURL: normalizedBaseURL
        )
    }

    private func rollback(
        preferences: AppPreferences?,
        googleKey: String??,
        llmKey: String??,
        launch: Bool?,
        shortcut: KeyboardShortcut?,
        restoreShortcut: Bool
    ) async -> Bool {
        var failed = false

        if let preferences {
            do { try await preferencesStore.save(preferences) } catch { failed = true }
        }
        if let llmKey {
            do { try restoreCredential(llmKey, key: .llmAPIKey) } catch { failed = true }
        }
        if let googleKey {
            do { try restoreCredential(googleKey, key: .googleAPIKey) } catch { failed = true }
        }
        if let launch, launchController.isEnabled != launch {
            do { try launchController.setEnabled(launch) } catch { failed = true }
        }
        if restoreShortcut {
            do { try shortcutRegistrar.register(shortcut, action: shortcutAction) } catch { failed = true }
        }
        return failed
    }

    private func storeCredential(_ value: String, key: CredentialKey) throws {
        if value.isEmpty {
            try credentialStore.delete(key)
        } else {
            try credentialStore.write(value, for: key)
        }
    }

    private func restoreCredential(_ value: String?, key: CredentialKey) throws {
        if let value {
            try credentialStore.write(value, for: key)
        } else {
            try credentialStore.delete(key)
        }
    }

    private func applySuccessfulSave(_ proposed: ProposedSettings) {
        launchAtLogin = proposed.preferences.launchAtLogin
        globalShortcut = proposed.preferences.globalShortcut
        translateClipboardOnOpen = proposed.preferences.translateClipboardOnOpen
        llmBaseURL = proposed.llmBaseURL
        llmModel = proposed.preferences.llmModel
        generalPrompt = proposed.preferences.generalPrompt
        technologyAndRnDPrompt = proposed.preferences.technologyAndRnDPrompt
        defaultPromptPresetID = proposed.preferences.defaultPromptPresetID
        googleAPIKey = proposed.googleAPIKey
        llmAPIKey = proposed.llmAPIKey
        session?.promptPresetID = proposed.preferences.defaultPromptPresetID
        providerAppearance.llmBrand = ProviderBrandResolver.resolve(baseURL: proposed.llmBaseURL)
        saveState = .saved
        saveError = nil
    }

    private func recordFailure(_ error: SettingsSaveError, rollbackIncomplete: Bool) {
        saveState = rollbackIncomplete ? .needsAttention : .failed
        saveError = error.localizedDescription
    }
}

private struct ProposedSettings {
    let preferences: AppPreferences
    let googleAPIKey: String
    let llmAPIKey: String
    let llmBaseURL: String
}
