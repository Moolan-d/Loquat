import AppKit
import OSLog
import SwiftUI
import InstantTranslationCore
import InstantTranslationFeature
import InstantTranslationInfrastructure

@MainActor
public final class ApplicationContainer {
    public let session: TranslationSession
    public let preferencesStore: any PreferencesStoring
    public let credentialStore: any CredentialStoring
    public let providerAppearance: ProviderAppearance
    public let statusBarController: StatusBarController
    public let popoverController: TranslationPopoverController
    public let settingsViewModel: SettingsViewModel
    public let settingsWindowController: SettingsWindowController

    private let shortcutRegistrar: GlobalShortcutRegistering
    private let clipboardSource: any InputSource
    private let logger = Logger(
        subsystem: "com.instanttranslation.macos",
        category: "application"
    )

    private init(
        session: TranslationSession,
        preferencesStore: any PreferencesStoring,
        credentialStore: any CredentialStoring,
        providerAppearance: ProviderAppearance,
        statusBarController: StatusBarController,
        popoverController: TranslationPopoverController,
        settingsViewModel: SettingsViewModel,
        settingsWindowController: SettingsWindowController,
        shortcutRegistrar: GlobalShortcutRegistering,
        clipboardSource: any InputSource
    ) {
        self.session = session
        self.preferencesStore = preferencesStore
        self.credentialStore = credentialStore
        self.providerAppearance = providerAppearance
        self.statusBarController = statusBarController
        self.popoverController = popoverController
        self.settingsViewModel = settingsViewModel
        self.settingsWindowController = settingsWindowController
        self.shortcutRegistrar = shortcutRegistrar
        self.clipboardSource = clipboardSource
    }

    public static func make(
        credentialConfiguration explicitConfiguration: ApplicationCredentialConfiguration? = nil
    ) async throws -> ApplicationContainer {
        let preferencesStore = UserDefaultsPreferencesStore()
        let credentialConfiguration = try explicitConfiguration
            ?? ApplicationCredentialConfiguration.resolve()
        let credentialStore = KeychainCredentialStore(
            backend: credentialConfiguration.backend
        )
        if let sourceBackend = credentialConfiguration.migrationSourceBackend {
            let source = KeychainCredentialStore(backend: sourceBackend)
            try CredentialMigrator(source: source, destination: credentialStore).migrate()
        }
        return await make(
            preferencesStore: preferencesStore,
            credentialStore: credentialStore,
            transport: URLSessionHTTPTransport(),
            launchAtLogin: LaunchAtLoginController(),
            shortcutRegistrar: CarbonGlobalShortcutRegistrar(),
            clipboardSource: ClipboardInputSource()
        )
    }

    static func make(
        preferencesStore: any PreferencesStoring,
        credentialStore: any CredentialStoring,
        transport: any HTTPTransport,
        launchAtLogin: LaunchAtLoginControlling,
        shortcutRegistrar: GlobalShortcutRegistering,
        clipboardSource: any InputSource,
        installApplicationMenu: Bool = true
    ) async -> ApplicationContainer {
        let google = GoogleTranslationProvider(transport: transport) {
            try credentialStore.read(.googleAPIKey)
        }
        let llm = OpenAICompatibleProvider(transport: transport) { presetID in
            let preferences = await preferencesStore.load()
            guard let apiKey = try credentialStore.read(.llmAPIKey),
                  !apiKey.isEmpty,
                  !preferences.llmBaseURL.isEmpty,
                  !preferences.llmModel.isEmpty
            else {
                return nil
            }
            let prompt = presetID == .general
                ? preferences.generalPrompt
                : preferences.technologyAndRnDPrompt
            return LLMProviderConfiguration(
                baseURL: preferences.llmBaseURL,
                apiKey: apiKey,
                model: preferences.llmModel,
                systemPrompt: prompt
            )
        }
        let preferences = await preferencesStore.load()
        let coordinator = TranslationCoordinator(providers: [google, llm])
        let session = TranslationSession(
            coordinator: coordinator,
            promptPresetID: preferences.defaultPromptPresetID,
            enabledProviderIDs: preferences.enabledProviderIDs
        )
        let appearance = ProviderAppearance(
            llmBrand: ProviderBrandResolver.resolve(baseURL: preferences.llmBaseURL)
        )
        // 凭据只在这里读一次并发布快照；窗口渲染路径不再触碰 Keychain。
        let availability = ProviderAvailability(
            configuredProviderIDs: ProviderAvailability.configuredProviderIDs(
                googleAPIKey: .of(Result { try credentialStore.read(.googleAPIKey) }),
                llmAPIKey: .of(Result { try credentialStore.read(.llmAPIKey) }),
                llmBaseURL: preferences.llmBaseURL,
                llmModel: preferences.llmModel
            )
        )
        let focusController = TranslationInputFocusController()
        let content = NSHostingView(
            rootView: TranslationView(
                session: session,
                appearance: appearance,
                availability: availability,
                focusController: focusController
            )
        )
        let popover = TranslationPopoverController(
            contentView: content,
            focusRequester: focusController
        )
        let statusBar = StatusBarController(
            popoverController: popover,
            shortcutRegistrar: shortcutRegistrar
        )
        let settingsViewModel = await SettingsViewModel.make(
            preferencesStore: preferencesStore,
            credentialStore: credentialStore,
            launchAtLogin: launchAtLogin,
            shortcutRegistrar: shortcutRegistrar,
            shortcutAction: { [weak statusBar] in
                statusBar?.toggleFromShortcut()
            },
            connectionTester: ProviderConnectionTester(transport: transport),
            providerAppearance: appearance,
            session: session
        )
        let settingsWindowController = SettingsWindowController(
            model: settingsViewModel,
            installApplicationMenu: installApplicationMenu
        )
        let container = ApplicationContainer(
            session: session,
            preferencesStore: preferencesStore,
            credentialStore: credentialStore,
            providerAppearance: appearance,
            statusBarController: statusBar,
            popoverController: popover,
            settingsViewModel: settingsViewModel,
            settingsWindowController: settingsWindowController,
            shortcutRegistrar: shortcutRegistrar,
            clipboardSource: clipboardSource
        )
        // 剪贴板读取只在快捷键唤起时触发（鼠标唤起永不读）；关闭动作不触发。
        statusBar.onShortcutOpen = { [weak container] in
            container?.prepareClipboard()
        }
        return container
    }

    public func start() {
        do {
            // 启动注册与设置保存同在 MainActor 顺序执行，避免异步旧偏好覆盖刚保存的新快捷键。
            try shortcutRegistrar.register(settingsViewModel.globalShortcut) {
                [weak statusBarController] in
                statusBarController?.toggleFromShortcut()
            }
        } catch {
            logger.error("shortcut registration failed")
        }
    }

    public func stop() {
        shortcutRegistrar.unregister()
        session.cancelAll()
    }

    private func prepareClipboard() {
        Task {
            let preferences = await preferencesStore.load()
            guard preferences.translateClipboardOnShortcut else { return }
            do {
                let text = try await clipboardSource.read()
                session.applyClipboardDecision(
                    ClipboardTextPolicy().evaluate(text?.value)
                )
            } catch {
                logger.error("clipboard read failed")
            }
        }
    }
}
