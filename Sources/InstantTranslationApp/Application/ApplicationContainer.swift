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
        shortcutRegistrar: GlobalShortcutRegistering,
        clipboardSource: any InputSource
    ) {
        self.session = session
        self.preferencesStore = preferencesStore
        self.credentialStore = credentialStore
        self.providerAppearance = providerAppearance
        self.statusBarController = statusBarController
        self.popoverController = popoverController
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
        let transport = URLSessionHTTPTransport()
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
            promptPresetID: preferences.defaultPromptPresetID
        )
        let appearance = ProviderAppearance(
            llmBrand: ProviderBrandResolver.resolve(baseURL: preferences.llmBaseURL)
        )
        let focusController = TranslationInputFocusController()
        let content = NSHostingView(
            rootView: TranslationView(
                session: session,
                appearance: appearance,
                focusController: focusController
            )
        )
        let popover = TranslationPopoverController(
            contentView: content,
            focusRequester: focusController
        )
        let shortcut = CarbonGlobalShortcutRegistrar()
        let statusBar = StatusBarController(
            popoverController: popover,
            shortcutRegistrar: shortcut
        )
        let container = ApplicationContainer(
            session: session,
            preferencesStore: preferencesStore,
            credentialStore: credentialStore,
            providerAppearance: appearance,
            statusBarController: statusBar,
            popoverController: popover,
            shortcutRegistrar: shortcut,
            clipboardSource: ClipboardInputSource()
        )
        popover.onWillShow = { [weak container] in
            container?.prepareClipboard()
        }
        return container
    }

    public func start() {
        Task {
            let preferences = await preferencesStore.load()
            do {
                try shortcutRegistrar.register(preferences.globalShortcut) {
                    [weak statusBarController] in
                    statusBarController?.toggleFromShortcut()
                }
            } catch {
                logger.error("shortcut registration failed")
            }
        }
    }

    public func stop() {
        shortcutRegistrar.unregister()
        session.cancelAll()
    }

    private func prepareClipboard() {
        Task {
            let preferences = await preferencesStore.load()
            guard preferences.translateClipboardOnOpen else { return }
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
