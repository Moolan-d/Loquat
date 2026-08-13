import Foundation
import InstantTranslationApp
import InstantTranslationCore
import InstantTranslationFeature
import InstantTranslationInfrastructure

public enum DiagnosticsLiveIOKind: Sendable {
    case urlSessionHTTPTransport
    case keychainCredentialStore
    case userDefaultsPreferencesStore
    case clipboardInputSource
}

public struct DiagnosticsLiveIOSnapshot: Equatable, Sendable {
    public let urlSessionHTTPTransport: Int
    public let keychainCredentialStore: Int
    public let userDefaultsPreferencesStore: Int
    public let clipboardInputSource: Int

    public static let zero = Self(
        urlSessionHTTPTransport: 0,
        keychainCredentialStore: 0,
        userDefaultsPreferencesStore: 0,
        clipboardInputSource: 0
    )
}

public final class DiagnosticsLiveIOAudit: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [DiagnosticsLiveIOKind: Int] = [:]

    public init() {}

    public func record(_ kind: DiagnosticsLiveIOKind) {
        lock.withLock { counts[kind, default: 0] += 1 }
    }

    public var snapshot: DiagnosticsLiveIOSnapshot {
        lock.withLock {
            DiagnosticsLiveIOSnapshot(
                urlSessionHTTPTransport: counts[.urlSessionHTTPTransport, default: 0],
                keychainCredentialStore: counts[.keychainCredentialStore, default: 0],
                userDefaultsPreferencesStore: counts[.userDefaultsPreferencesStore, default: 0],
                clipboardInputSource: counts[.clipboardInputSource, default: 0]
            )
        }
    }
}

public struct DiagnosticsLiveIOFactories: Sendable {
    public let makeHTTPTransport: @Sendable () -> any HTTPTransport
    public let makeCredentialStore: @Sendable () -> any CredentialStoring
    public let makePreferencesStore: @Sendable () -> any PreferencesStoring
    public let makeClipboardSource: @Sendable () -> any InputSource

    public init(
        makeHTTPTransport: @escaping @Sendable () -> any HTTPTransport,
        makeCredentialStore: @escaping @Sendable () -> any CredentialStoring,
        makePreferencesStore: @escaping @Sendable () -> any PreferencesStoring,
        makeClipboardSource: @escaping @Sendable () -> any InputSource
    ) {
        self.makeHTTPTransport = makeHTTPTransport
        self.makeCredentialStore = makeCredentialStore
        self.makePreferencesStore = makePreferencesStore
        self.makeClipboardSource = makeClipboardSource
    }

    public static let prohibited = Self(
        makeHTTPTransport: { fatalError("Diagnostics must not construct live HTTP") },
        makeCredentialStore: { fatalError("Diagnostics must not construct live Keychain") },
        makePreferencesStore: { fatalError("Diagnostics must not construct live UserDefaults") },
        makeClipboardSource: { fatalError("Diagnostics must not read the live pasteboard") }
    )
}

public enum DiagnosticsFixtureError: Error, Sendable {
    case injectedPersistenceFailure
    case injectedCredentialFailure
}

public actor DiagnosticsMemoryPreferencesStore: PreferencesStoring {
    enum SaveFailure {
        case beforeMutation
        case afterMutation
    }

    private var value: AppPreferences
    private var saveFailures: [SaveFailure]
    public private(set) var saveAttemptCount = 0

    init(
        value: AppPreferences,
        saveFailures: [SaveFailure] = []
    ) {
        self.value = value
        self.saveFailures = saveFailures
    }

    public func load() -> AppPreferences {
        value
    }

    public func save(_ preferences: AppPreferences) throws {
        saveAttemptCount += 1
        let failure = saveFailures.isEmpty ? nil : saveFailures.removeFirst()
        if failure == .beforeMutation {
            throw DiagnosticsFixtureError.injectedPersistenceFailure
        }
        value = preferences
        if failure == .afterMutation {
            throw DiagnosticsFixtureError.injectedPersistenceFailure
        }
    }
}

public final class DiagnosticsMemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [CredentialKey: String]
    private var readFailuresRemaining: Int

    init(values: [CredentialKey: String], readFailuresRemaining: Int = 0) {
        self.values = values
        self.readFailuresRemaining = readFailuresRemaining
    }

    public func read(_ key: CredentialKey) throws -> String? {
        try lock.withLock {
            if readFailuresRemaining > 0 {
                readFailuresRemaining -= 1
                throw DiagnosticsFixtureError.injectedCredentialFailure
            }
            return values[key]
        }
    }

    public func write(_ value: String, for key: CredentialKey) {
        lock.withLock { values[key] = value }
    }

    public func delete(_ key: CredentialKey) {
        _ = lock.withLock { values.removeValue(forKey: key) }
    }
}

public actor DiagnosticsTranslationProvider: TranslationProvider {
    public nonisolated let id: ProviderID
    private let behavior: DiagnosticsProviderBehavior
    private var pending: [PendingRequest] = []
    private var completeBeforeSuspension = false

    init(id: ProviderID, behavior: DiagnosticsProviderBehavior) {
        self.id = id
        self.behavior = behavior
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        switch behavior {
        case .success(let primaryText):
            return result(primaryText: primaryText, request: request)
        case .failure(let error):
            throw error
        case .pending(let primaryText):
            if completeBeforeSuspension {
                return result(primaryText: primaryText, request: request)
            }
            return try await withCheckedThrowingContinuation { continuation in
                pending.append(PendingRequest(request: request, continuation: continuation))
            }
        }
    }

    public func completePending() {
        guard case .pending(let primaryText) = behavior else { return }
        guard !pending.isEmpty else {
            completeBeforeSuspension = true
            return
        }
        let continuations = pending
        pending.removeAll()
        for pendingRequest in continuations {
            pendingRequest.continuation.resume(
                returning: result(primaryText: primaryText, request: pendingRequest.request)
            )
        }
    }

    private func result(
        primaryText: String,
        request: TranslationRequest
    ) -> TranslationResult {
        TranslationResult(
            providerID: id,
            requestID: request.id,
            primaryText: primaryText,
            rationale: nil,
            sourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage,
            pronunciations: [],
            speakableText: primaryText,
            duration: .milliseconds(5)
        )
    }
}

private struct PendingRequest {
    let request: TranslationRequest
    let continuation: CheckedContinuation<TranslationResult, any Error>
}

actor DiagnosticsConnectionTester: ProviderConnectionTesting {
    private let googleBehavior: DiagnosticsProviderBehavior
    private let llmBehavior: DiagnosticsProviderBehavior

    init(
        googleBehavior: DiagnosticsProviderBehavior,
        llmBehavior: DiagnosticsProviderBehavior
    ) {
        self.googleBehavior = googleBehavior
        self.llmBehavior = llmBehavior
    }

    func testGoogle(apiKey: String) -> ConnectionTestState {
        state(for: googleBehavior)
    }

    func testLLM(configuration: LLMProviderConfiguration) -> ConnectionTestState {
        state(for: llmBehavior)
    }

    private func state(for behavior: DiagnosticsProviderBehavior) -> ConnectionTestState {
        if case .failure(let error) = behavior {
            return .failure(error)
        }
        return .success
    }
}

@MainActor
final class DiagnosticsLaunchAtLoginController: LaunchAtLoginControlling {
    var status = LaunchAtLoginStatus.notRegistered

    func setEnabled(_ enabled: Bool) {
        status = enabled ? .enabled : .notRegistered
    }
}

@MainActor
final class DiagnosticsShortcutRegistrar: GlobalShortcutRegistering {
    private(set) var registeredShortcut: KeyboardShortcut?

    func register(
        _ shortcut: KeyboardShortcut?,
        action: @escaping @MainActor () -> Void
    ) {
        registeredShortcut = shortcut
    }

    func unregister() {
        registeredShortcut = nil
    }
}

@MainActor
public final class DiagnosticsComposition {
    public let session: TranslationSession
    public let settingsViewModel: SettingsViewModel
    public let preferencesStore: DiagnosticsMemoryPreferencesStore
    public let credentialStore: DiagnosticsMemoryCredentialStore
    let providerAppearance: ProviderAppearance
    let shortcutRegistrar: DiagnosticsShortcutRegistrar
    private let googleProvider: DiagnosticsTranslationProvider
    private let llmProvider: DiagnosticsTranslationProvider

    init(
        session: TranslationSession,
        settingsViewModel: SettingsViewModel,
        preferencesStore: DiagnosticsMemoryPreferencesStore,
        credentialStore: DiagnosticsMemoryCredentialStore,
        providerAppearance: ProviderAppearance,
        shortcutRegistrar: DiagnosticsShortcutRegistrar,
        googleProvider: DiagnosticsTranslationProvider,
        llmProvider: DiagnosticsTranslationProvider
    ) {
        self.session = session
        self.settingsViewModel = settingsViewModel
        self.preferencesStore = preferencesStore
        self.credentialStore = credentialStore
        self.providerAppearance = providerAppearance
        self.shortcutRegistrar = shortcutRegistrar
        self.googleProvider = googleProvider
        self.llmProvider = llmProvider
    }

    public func completeSlowRequest() async {
        await googleProvider.completePending()
        await llmProvider.completePending()
    }
}

public enum DiagnosticsDependencies {
    @MainActor
    public static func makeComposition(
        for scenario: DiagnosticsScenario,
        liveIOFactories: DiagnosticsLiveIOFactories = .prohibited
    ) async -> DiagnosticsComposition {
        // 参数是运行时保险丝：新增依赖若误用任一工厂，zero-I/O 测试会立刻记录并失败。
        _ = liveIOFactories
        let configuration = scenario.configuration
        var preferences = AppPreferences()
        preferences.llmBaseURL = "https://diagnostics.invalid/v1"
        preferences.llmModel = DiagnosticsFixtures.llmModel
        preferences.generalPrompt = DiagnosticsFixtures.prompt
        preferences.technologyAndRnDPrompt = DiagnosticsFixtures.prompt

        let preferenceFailures: [DiagnosticsMemoryPreferencesStore.SaveFailure]
        if scenario == .rollbackIncomplete {
            preferenceFailures = [.afterMutation, .beforeMutation]
        } else {
            preferenceFailures = []
        }
        let preferencesStore = DiagnosticsMemoryPreferencesStore(
            value: preferences,
            saveFailures: preferenceFailures
        )
        let credentialStore = DiagnosticsMemoryCredentialStore(
            values: [
                .googleAPIKey: DiagnosticsFixtures.googleCredential,
                .llmAPIKey: DiagnosticsFixtures.llmCredential,
            ],
            readFailuresRemaining: scenario == .credentialReload ? 2 : 0
        )
        let googleProvider = DiagnosticsTranslationProvider(
            id: .google,
            behavior: configuration.googleBehavior
        )
        let llmProvider = DiagnosticsTranslationProvider(
            id: .llm,
            behavior: configuration.llmBehavior
        )
        let session = TranslationSession(
            coordinator: TranslationCoordinator(providers: [googleProvider, llmProvider]),
            promptPresetID: preferences.defaultPromptPresetID
        )
        let appearance = ProviderAppearance(llmBrand: .genericAI)
        let shortcut = DiagnosticsShortcutRegistrar()
        let settings = await SettingsViewModel.make(
            preferencesStore: preferencesStore,
            credentialStore: credentialStore,
            launchAtLogin: DiagnosticsLaunchAtLoginController(),
            shortcutRegistrar: shortcut,
            shortcutAction: {},
            connectionTester: DiagnosticsConnectionTester(
                googleBehavior: configuration.googleBehavior,
                llmBehavior: configuration.llmBehavior
            ),
            providerAppearance: appearance,
            session: session
        )
        let composition = DiagnosticsComposition(
            session: session,
            settingsViewModel: settings,
            preferencesStore: preferencesStore,
            credentialStore: credentialStore,
            providerAppearance: appearance,
            shortcutRegistrar: shortcut,
            googleProvider: googleProvider,
            llmProvider: llmProvider
        )

        switch configuration.destination {
        case .translationPopover:
            session.submit(rawText: configuration.initialInput, sourceID: .manual)
        case .settings where scenario == .rollbackIncomplete:
            settings.translateClipboardOnOpen.toggle()
            do {
                try await settings.save()
            } catch {
                // 此场景刻意展示正式 SettingsViewModel 的 rollback-incomplete 公开状态。
            }
        case .settings:
            break
        }
        return composition
    }
}
