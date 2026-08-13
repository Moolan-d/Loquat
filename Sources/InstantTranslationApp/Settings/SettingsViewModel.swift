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

public enum CredentialAccessState: Equatable, Sendable {
    case loaded
    case unavailable
}

public enum SettingsSaveError: Error, Equatable, Sendable {
    case invalidLLMConfiguration
    case invalidPrompt
    case insecureEndpoint
    case credentialsUnavailable
    case saveInProgress
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
        case .credentialsUnavailable:
            "Credentials are unavailable. Reload them and try again."
        case .saveInProgress:
            "Settings are already being saved."
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
    public private(set) var credentialAccessState: CredentialAccessState
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
        let credentials = loadCredentials(from: credentialStore)
        return SettingsViewModel(
            preferences: preferences,
            googleAPIKey: credentials.googleAPIKey ?? "",
            llmAPIKey: credentials.llmAPIKey ?? "",
            credentialAccessState: credentials.state,
            actualLaunchAtLogin: launchAtLogin.status.isRegistered,
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
        credentialAccessState: CredentialAccessState,
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
        self.credentialAccessState = credentialAccessState
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
        guard saveState != .saving else {
            throw SettingsSaveError.saveInProgress
        }
        saveState = .saving
        saveError = nil

        guard credentialAccessState == .loaded else {
            let publicError = SettingsSaveError.credentialsUnavailable
            recordFailure(publicError, rollbackIncomplete: false)
            throw publicError
        }

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
        let credentialSnapshot = Self.loadCredentials(from: credentialStore)
        guard credentialSnapshot.state == .loaded else {
            credentialAccessState = .unavailable
            let publicError = SettingsSaveError.credentialsUnavailable
            recordFailure(publicError, rollbackIncomplete: false)
            throw publicError
        }
        let oldGoogleKey = credentialSnapshot.googleAPIKey
        let oldLLMKey = credentialSnapshot.llmAPIKey
        let oldLaunch = launchController.status.isRegistered
        let oldShortcut = shortcutRegistrar.registeredShortcut

        var shortcutAttempted = false
        var launchAttempted = false
        var googleCredentialAttempted = false
        var llmCredentialAttempted = false
        var preferencesAttempted = false

        do {
            // 快捷键与登录项先变更，偏好最后提交；失败时使用旧快照逆序补偿外部状态。
            shortcutAttempted = true
            try shortcutRegistrar.register(proposed.preferences.globalShortcut, action: shortcutAction)

            if launchController.status.isRegistered != proposed.preferences.launchAtLogin {
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
                shortcut: oldShortcut,
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

    public func reloadCredentials() {
        let credentials = Self.loadCredentials(from: credentialStore)
        guard credentials.state == .loaded else {
            credentialAccessState = .unavailable
            return
        }
        googleAPIKey = credentials.googleAPIKey ?? ""
        llmAPIKey = credentials.llmAPIKey ?? ""
        credentialAccessState = .loaded
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
            configuration = try validatedLLMConnectionConfiguration()
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

    private func validatedLLMConnectionConfiguration() throws -> LLMProviderConfiguration {
        let baseURL = llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = llmModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedPrompt = (
            defaultPromptPresetID == .general ? generalPrompt : technologyAndRnDPrompt
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty, !apiKey.isEmpty, !model.isEmpty, !selectedPrompt.isEmpty else {
            throw SettingsSaveError.invalidLLMConfiguration
        }
        let normalizedBaseURL: String
        do {
            normalizedBaseURL = try EndpointPolicy.validatedAPIBaseURL(baseURL).absoluteString
        } catch {
            throw SettingsSaveError.insecureEndpoint
        }
        return LLMProviderConfiguration(
            baseURL: normalizedBaseURL,
            apiKey: apiKey,
            model: model,
            systemPrompt: selectedPrompt
        )
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
        if let launch, launchController.status.isRegistered != launch {
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

    private static func loadCredentials(
        from store: any CredentialStoring
    ) -> LoadedCredentials {
        let googleResult = Result { try store.read(.googleAPIKey) }
        let llmResult = Result { try store.read(.llmAPIKey) }
        switch (googleResult, llmResult) {
        case let (.success(googleAPIKey), .success(llmAPIKey)):
            return LoadedCredentials(
                googleAPIKey: googleAPIKey,
                llmAPIKey: llmAPIKey,
                state: .loaded
            )
        default:
            // 任一 Keychain 读取失败时，不发布部分密钥；显式不可用状态会阻止保存覆盖未知值。
            return LoadedCredentials(
                googleAPIKey: nil,
                llmAPIKey: nil,
                state: .unavailable
            )
        }
    }
}

private struct ProposedSettings {
    let preferences: AppPreferences
    let googleAPIKey: String
    let llmAPIKey: String
    let llmBaseURL: String
}

private struct LoadedCredentials {
    let googleAPIKey: String?
    let llmAPIKey: String?
    let state: CredentialAccessState
}
