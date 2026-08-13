import AppKit
import Carbon.HIToolbox
import SwiftUI
import XCTest
import InstantTranslationCore
import InstantTranslationFeature
import InstantTranslationInfrastructure
@testable import InstantTranslationApp

@MainActor
final class SettingsPresentationTests: XCTestCase {
    func testPresentationPolicyHasOnlyTheThreeSettingsGroups() {
        XCTAssertEqual(
            SettingsPresentationPolicy.functionalGroups,
            [.general, .translationServices, .llmPrompts]
        )
    }

    func testUnavailableCredentialsExposeReloadAndDisableSecretEditingAndSave() async {
        let credentials = MemoryCredentialStore(values: [
            .googleAPIKey: "google-secret",
            .llmAPIKey: "llm-secret",
        ])
        credentials.failNextRead(.googleAPIKey)
        let model = await makeModel(credentials: credentials)

        var policy = SettingsPresentationPolicy(model: model)
        XCTAssertFalse(policy.credentialsEditable)
        XCTAssertFalse(policy.saveEnabled)
        XCTAssertTrue(policy.showsCredentialReload)
        XCTAssertEqual(
            policy.credentialStatus,
            "Credentials are unavailable. Reload them to edit or save settings."
        )

        model.reloadCredentials()
        policy = SettingsPresentationPolicy(model: model)

        XCTAssertTrue(policy.credentialsEditable)
        XCTAssertTrue(policy.saveEnabled)
        XCTAssertFalse(policy.showsCredentialReload)
        XCTAssertEqual(model.googleAPIKey, "google-secret")
        XCTAssertEqual(model.llmAPIKey, "llm-secret")
    }

    func testSavePresentationDifferentiatesEveryStateAndPreventsDuplicateSave() async {
        let model = await makeModel()

        XCTAssertEqual(
            SettingsPresentationPolicy(model: model).saveStatus,
            .init(message: "Ready to save.", emphasis: .secondary)
        )

        let preferences = SuspendingPreferencesStore()
        let savingModel = await SettingsViewModel.make(
            preferencesStore: preferences,
            credentialStore: MemoryCredentialStore(),
            launchAtLogin: FakeLaunchAtLoginController(),
            shortcutRegistrar: FakeSettingsShortcutRegistrar(),
            shortcutAction: {},
            connectionTester: RecordingConnectionTester(),
            providerAppearance: ProviderAppearance(llmBrand: .genericAI),
            session: nil
        )
        await preferences.suspendNextLoad()
        let save = Task { try await savingModel.save() }
        await preferences.waitUntilLoadSuspends()

        let savingPolicy = SettingsPresentationPolicy(model: savingModel)
        XCTAssertFalse(savingPolicy.saveEnabled)
        XCTAssertEqual(
            savingPolicy.saveStatus,
            .init(message: "Saving settings…", emphasis: .secondary)
        )
        await preferences.resumeLoad()
        do {
            try await save.value
        } catch {
            XCTFail("Expected suspended save to finish: \(error)")
        }

        XCTAssertEqual(
            SettingsPresentationPolicy(model: savingModel).saveStatus,
            .init(message: "Settings saved.", emphasis: .success)
        )

        model.generalPrompt = ""
        await SettingsViewActions(model: model).save()
        XCTAssertEqual(
            SettingsPresentationPolicy(model: model).saveStatus,
            .init(message: "Prompts cannot be empty.", emphasis: .error)
        )

        let rollbackModel = await makeRollbackFailureModel()
        await SettingsViewActions(model: rollbackModel).save()
        XCTAssertEqual(
            SettingsPresentationPolicy(model: rollbackModel).saveStatus,
            .init(
                message: "Some changes may not have been fully restored. Review settings and retry.",
                emphasis: .critical
            )
        )
    }

    func testConnectionPresentationIsProviderSpecificAndDisablesOnlyTestingProvider() {
        let google = SettingsPresentationPolicy.connectionStatus(
            provider: .google,
            state: .testing
        )
        let llm = SettingsPresentationPolicy.connectionStatus(
            provider: .llm,
            state: .failure(.invalidCredentials)
        )

        XCTAssertEqual(
            google,
            .init(message: "Google: Testing…", emphasis: .secondary)
        )
        XCTAssertEqual(
            llm,
            .init(message: "LLM: Authentication failed.", emphasis: .error)
        )
        XCTAssertFalse(
            SettingsPresentationPolicy.connectionTestEnabled(
                provider: .google,
                googleState: .testing,
                llmState: .success
            )
        )
        XCTAssertTrue(
            SettingsPresentationPolicy.connectionTestEnabled(
                provider: .llm,
                googleState: .testing,
                llmState: .success
            )
        )
    }

    func testConnectionPresentationMapsEveryProviderErrorWithoutSensitiveDetails() {
        let cases: [(TranslationProviderError, String)] = [
            (.unconfigured, "Configuration is incomplete."),
            (.invalidCredentials, "Authentication failed."),
            (.rateLimited, "Rate limited."),
            (.networkUnavailable, "Network unavailable."),
            (.timedOut, "Timed out."),
            (.insecureEndpoint, "Base URL is not allowed."),
            (.invalidResponse, "Invalid response."),
            (.server(statusCode: 503), "Service error (503)."),
            (.cancelled, "Cancelled."),
        ]

        XCTAssertNil(
            SettingsPresentationPolicy.connectionStatus(provider: .google, state: .idle)
        )
        XCTAssertEqual(
            SettingsPresentationPolicy.connectionStatus(provider: .llm, state: .success),
            .init(message: "LLM: Connected.", emphasis: .success)
        )
        for (error, message) in cases {
            XCTAssertEqual(
                SettingsPresentationPolicy.connectionStatus(
                    provider: .google,
                    state: .failure(error)
                ),
                .init(message: "Google: \(message)", emphasis: .error)
            )
        }
    }

    func testViewActionsRunConnectionTestsOnlyFromExplicitProviderActions() async {
        let tester = RecordingConnectionTester()
        let model = await makeModel(connectionTester: tester)
        let actions = SettingsViewActions(model: model)
        model.googleAPIKey = "google-key"
        model.llmBaseURL = "https://api.example.com/v1"
        model.llmAPIKey = "llm-key"
        model.llmModel = "llm-model"

        await actions.save()
        var googleKeys = await tester.googleKeys
        var llmConfigurations = await tester.llmConfigurations
        XCTAssertEqual(googleKeys.count, 0)
        XCTAssertEqual(llmConfigurations.count, 0)

        await actions.testGoogleConnection()
        googleKeys = await tester.googleKeys
        llmConfigurations = await tester.llmConfigurations
        XCTAssertEqual(googleKeys, ["google-key"])
        XCTAssertEqual(llmConfigurations.count, 0)

        await actions.testLLMConnection()
        googleKeys = await tester.googleKeys
        llmConfigurations = await tester.llmConfigurations
        XCTAssertEqual(googleKeys.count, 1)
        XCTAssertEqual(llmConfigurations.count, 1)
    }

    func testSettingsViewRegistryExposesRealGroupsControlsAndUnavailableCredentialActions() async {
        let credentials = MemoryCredentialStore(values: [
            .googleAPIKey: "google-secret",
            .llmAPIKey: "llm-secret",
        ])
        credentials.failNextRead(.googleAPIKey)
        let model = await makeModel(credentials: credentials)
        let registry = SettingsViewRegistry(model: model)
        XCTAssertEqual(
            registry.groups,
            [.general, .translationServices, .llmPrompts]
        )
        XCTAssertEqual(Set(registry.controls.map(\.id)), Set(SettingsControlID.allCases))
        XCTAssertTrue(
            registry.controls.allSatisfy {
                !$0.accessibilityLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        )
        XCTAssertEqual(
            Set(registry.controls.filter { $0.group == .general }.map(\.id)),
            [.launchAtLogin, .clipboardOnOpen, .globalShortcut]
        )
        XCTAssertEqual(
            Set(registry.controls.filter { $0.group == .translationServices }.map(\.id)),
            [
                .credentialStatus,
                .reloadCredentials,
                .googleAPIKey,
                .googleTest,
                .googleStatus,
                .llmBaseURL,
                .llmAPIKey,
                .llmModel,
                .llmTest,
                .llmStatus,
                .connectionWarning,
            ]
        )
        XCTAssertEqual(
            Set(registry.controls.filter { $0.group == .llmPrompts }.map(\.id)),
            [
                .promptPreset,
                .generalPrompt,
                .restoreGeneralPrompt,
                .technologyPrompt,
                .restoreTechnologyPrompt,
            ]
        )
        XCTAssertEqual(
            registry.control(.launchAtLogin).accessibilityLabel,
            "Launch Instant Translation at login"
        )
        XCTAssertEqual(
            registry.control(.googleAPIKey).accessibilityLabel,
            "Google Cloud Translation API key"
        )
        XCTAssertEqual(
            registry.control(.llmTest).accessibilityLabel,
            "Test LLM connection"
        )
        XCTAssertFalse(registry.control(.googleAPIKey).isEnabled)
        XCTAssertFalse(registry.control(.llmAPIKey).isEnabled)
        XCTAssertFalse(registry.control(.save).isEnabled)
        XCTAssertTrue(registry.control(.reloadCredentials).isVisible)
        XCTAssertEqual(
            registry.control(.credentialStatus).value,
            "Credentials are unavailable. Reload them to edit or save settings."
        )

        await registry.perform(.reloadCredentials)

        XCTAssertEqual(model.credentialAccessState, .loaded)
        let reloaded = SettingsViewRegistry(model: model)
        XCTAssertTrue(reloaded.control(.googleAPIKey).isEnabled)
        XCTAssertTrue(reloaded.control(.llmAPIKey).isEnabled)
        XCTAssertTrue(reloaded.control(.save).isEnabled)
        XCTAssertFalse(reloaded.control(.reloadCredentials).isVisible)
    }

    func testSettingsViewRegistrySaveRunsSaveAndReflectsSavingThenSaved() async {
        let preferences = SuspendingPreferencesStore()
        let model = await SettingsViewModel.make(
            preferencesStore: preferences,
            credentialStore: MemoryCredentialStore(),
            launchAtLogin: FakeLaunchAtLoginController(),
            shortcutRegistrar: FakeSettingsShortcutRegistrar(),
            shortcutAction: {},
            connectionTester: RecordingConnectionTester(),
            providerAppearance: ProviderAppearance(llmBrand: .genericAI),
            session: nil
        )
        await preferences.suspendNextLoad()

        let save = Task { await SettingsViewRegistry(model: model).perform(.save) }
        await preferences.waitUntilLoadSuspends()

        XCTAssertEqual(model.saveState, .saving)
        XCTAssertFalse(SettingsViewRegistry(model: model).control(.save).isEnabled)
        XCTAssertEqual(
            SettingsViewRegistry(model: model).control(.saveStatus).value,
            "Saving settings…"
        )

        await preferences.resumeLoad()
        await save.value

        XCTAssertEqual(model.saveState, .saved)
        XCTAssertTrue(SettingsViewRegistry(model: model).control(.save).isEnabled)
        XCTAssertEqual(
            SettingsViewRegistry(model: model).control(.saveStatus).value,
            "Settings saved."
        )
    }

    func testSettingsViewRegistryRoutesEachConnectionControlToItsProvider() async {
        let tester = RecordingConnectionTester()
        let model = await makeModel(connectionTester: tester)
        model.googleAPIKey = "google-key"
        model.llmBaseURL = "https://api.example.com/v1"
        model.llmAPIKey = "llm-key"
        model.llmModel = "llm-model"
        let registry = SettingsViewRegistry(model: model)

        await registry.perform(.googleTest)
        var googleKeys = await tester.googleKeys
        var llmConfigurations = await tester.llmConfigurations
        XCTAssertEqual(googleKeys, ["google-key"])
        XCTAssertEqual(llmConfigurations.count, 0)

        await registry.perform(.llmTest)
        googleKeys = await tester.googleKeys
        llmConfigurations = await tester.llmConfigurations
        XCTAssertEqual(googleKeys.count, 1)
        XCTAssertEqual(llmConfigurations.count, 1)
    }

    func testSettingsViewRegistryRoutesEachRestoreControlToItsPrompt() async {
        let model = await makeModel()
        let registry = SettingsViewRegistry(model: model)
        model.generalPrompt = "custom general"
        model.technologyAndRnDPrompt = "custom technology"

        await registry.perform(.restoreGeneralPrompt)
        XCTAssertNotEqual(model.generalPrompt, "custom general")
        XCTAssertEqual(model.technologyAndRnDPrompt, "custom technology")

        await registry.perform(.restoreTechnologyPrompt)
        XCTAssertNotEqual(model.technologyAndRnDPrompt, "custom technology")
    }

    func testSettingsViewRegistryConnectionActionsRouteToCorrectProviderAndDisableIndependently() async {
        let tester = ControlledConnectionTester()
        let model = await makeModel(connectionTester: tester)
        model.googleAPIKey = "google-key"
        model.llmBaseURL = "https://api.example.com/v1"
        model.llmAPIKey = "llm-key"
        model.llmModel = "llm-model"
        let google = Task { await SettingsViewRegistry(model: model).perform(.googleTest) }
        while await tester.googleCallCount() == 0 {
            await Task.yield()
        }

        var googleCallCount = await tester.googleCallCount()
        var llmCallCount = await tester.llmCallCount()
        XCTAssertEqual(llmCallCount, 0)
        XCTAssertFalse(SettingsViewRegistry(model: model).control(.googleTest).isEnabled)
        XCTAssertTrue(SettingsViewRegistry(model: model).control(.llmTest).isEnabled)
        XCTAssertEqual(
            SettingsViewRegistry(model: model).control(.googleStatus).value,
            "Google: Testing…"
        )

        await tester.completeGoogle(at: 0, with: .success)
        await google.value

        let llm = Task { await SettingsViewRegistry(model: model).perform(.llmTest) }
        while await tester.llmCallCount() == 0 {
            await Task.yield()
        }

        googleCallCount = await tester.googleCallCount()
        llmCallCount = await tester.llmCallCount()
        XCTAssertEqual(googleCallCount, 1)
        XCTAssertEqual(llmCallCount, 1)
        XCTAssertTrue(SettingsViewRegistry(model: model).control(.googleTest).isEnabled)
        XCTAssertFalse(SettingsViewRegistry(model: model).control(.llmTest).isEnabled)
        XCTAssertEqual(
            SettingsViewRegistry(model: model).control(.llmStatus).value,
            "LLM: Testing…"
        )

        await tester.completeLLM(at: 0, with: .success)
        await llm.value
    }

    func testSettingsControllerReusesWindowAcrossCloseShowAndNotification() async throws {
        let center = NotificationCenter()
        var activationCount = 0
        var orderedWindows: [NSWindow] = []
        var routedToKeyAndFront = false
        let controller = SettingsWindowController(
            model: await makeModel(),
            notificationCenter: center,
            activateApplication: { activationCount += 1 },
            orderWindowFront: { window, sender in
                orderedWindows.append(window)
                routedToKeyAndFront = true
                window.makeKeyAndOrderFront(sender)
            },
            installApplicationMenu: false
        )
        XCTAssertFalse(controller.isSettingsWindowConstructed)
        controller.showSettings(nil)
        let originalWindow = try XCTUnwrap(controller.window)
        XCTAssertFalse(originalWindow.isReleasedWhenClosed)

        XCTAssertTrue(originalWindow.isVisible)
        XCTAssertTrue(orderedWindows.last === originalWindow)
        XCTAssertTrue(routedToKeyAndFront)
        XCTAssertEqual(activationCount, 1)

        originalWindow.close()
        routedToKeyAndFront = false
        center.post(name: .openInstantTranslationSettings, object: nil)

        XCTAssertTrue(controller.window === originalWindow)
        XCTAssertTrue(originalWindow.isVisible)
        XCTAssertEqual(orderedWindows.count, 2)
        XCTAssertTrue(orderedWindows.last === originalWindow)
        XCTAssertTrue(routedToKeyAndFront)
        XCTAssertEqual(activationCount, 2)
        originalWindow.orderOut(nil)
    }

    func testSettingsWindowIsConstructedOnlyOnFirstPresentation() async {
        var constructionCount = 0
        let controller = SettingsWindowController(
            model: await makeModel(),
            notificationCenter: NotificationCenter(),
            activateApplication: {},
            orderWindowFront: { window, sender in window.makeKeyAndOrderFront(sender) },
            installApplicationMenu: false,
            makeWindow: { model in
                constructionCount += 1
                return SettingsWindowController.makeProductionWindow(model: model)
            }
        )

        XCTAssertFalse(controller.isSettingsWindowConstructed)
        XCTAssertEqual(constructionCount, 0)
        controller.showSettings(nil)
        let firstWindow = controller.window
        XCTAssertTrue(controller.isSettingsWindowConstructed)
        XCTAssertEqual(constructionCount, 1)
        firstWindow?.close()
        controller.showSettings(nil)
        XCTAssertTrue(controller.window === firstWindow)
        XCTAssertEqual(constructionCount, 1)
        controller.window?.orderOut(nil)
    }

    func testReentrantOpenNotificationDuringConstructionCoalescesOnePresentation() async {
        let center = NotificationCenter()
        var constructionCount = 0
        var postedNestedOpen = false
        var activationCount = 0
        var orderedWindows: [NSWindow] = []
        let controller = SettingsWindowController(
            model: await makeModel(),
            notificationCenter: center,
            activateApplication: { activationCount += 1 },
            orderWindowFront: { window, _ in orderedWindows.append(window) },
            installApplicationMenu: false,
            makeWindow: { model in
                constructionCount += 1
                if !postedNestedOpen {
                    postedNestedOpen = true
                    center.post(name: .openInstantTranslationSettings, object: nil)
                }
                return SettingsWindowController.makeProductionWindow(model: model)
            }
        )

        controller.showSettings(nil)

        XCTAssertTrue(controller.isSettingsWindowConstructed)
        XCTAssertEqual(constructionCount, 1)
        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(orderedWindows.count, 1)
        XCTAssertTrue(orderedWindows.first === controller.window)
        controller.window?.orderOut(nil)
    }

    func testApplicationMenuRoutesSettingsAndRetainsQuitCommand() async throws {
        let application = NSApplication.shared
        let previousMenu = application.mainMenu
        defer { application.mainMenu = previousMenu }
        var activationCount = 0
        let controller = SettingsWindowController(
            model: await makeModel(),
            notificationCenter: NotificationCenter(),
            activateApplication: { activationCount += 1 },
            orderWindowFront: { window, sender in
                window.makeKeyAndOrderFront(sender)
            },
            installApplicationMenu: true
        )
        let appMenu = try XCTUnwrap(application.mainMenu?.items.first?.submenu)
        let settings = try XCTUnwrap(appMenu.items.first { $0.keyEquivalent == "," })
        let quit = try XCTUnwrap(appMenu.items.first { $0.keyEquivalent == "q" })

        XCTAssertEqual(settings.action, #selector(SettingsWindowController.showSettings(_:)))
        XCTAssertTrue(settings.target === controller)
        XCTAssertEqual(quit.action, #selector(NSApplication.terminate(_:)))
        XCTAssertTrue(quit.target === application)

        XCTAssertTrue(
            application.sendAction(settings.action!, to: settings.target, from: settings)
        )
        XCTAssertEqual(activationCount, 1)
        XCTAssertTrue(controller.window?.isVisible == true)
        controller.window?.orderOut(nil)
    }

    func testInjectedContainerSharesSettingsRuntimeDependencies() async throws {
        let application = NSApplication.shared
        let originalMenu = application.mainMenu
        var preferencesValue = AppPreferences()
        preferencesValue.defaultPromptPresetID = .general
        let preferences = MemoryPreferencesStore(preferencesValue)
        let credentials = MemoryCredentialStore()
        let shortcut = FakeSettingsShortcutRegistrar()
        let container = await ApplicationContainer.make(
            preferencesStore: preferences,
            credentialStore: credentials,
            transport: RecordingHTTPTransport(responses: []),
            launchAtLogin: FakeLaunchAtLoginController(),
            shortcutRegistrar: shortcut,
            clipboardSource: EmptyInputSource(),
            installApplicationMenu: false
        )

        XCTAssertTrue(application.mainMenu === originalMenu)
        XCTAssertTrue(container.settingsWindowController.model === container.settingsViewModel)
        container.settingsViewModel.defaultPromptPresetID = .technologyAndRnD
        container.settingsViewModel.globalShortcut = KeyboardShortcut(
            keyCode: 0,
            carbonModifiers: UInt32(cmdKey)
        )
        container.settingsViewModel.llmBaseURL = "https://api.openai.com/v1"
        container.settingsViewModel.llmAPIKey = "llm-key"
        container.settingsViewModel.llmModel = "gpt-5-mini"

        try await container.settingsViewModel.save()

        XCTAssertEqual(container.session.promptPresetID, .technologyAndRnD)
        XCTAssertEqual(container.providerAppearance.llmBrand, .openAI)
        XCTAssertEqual(
            shortcut.registeredShortcut,
            KeyboardShortcut(keyCode: 0, carbonModifiers: UInt32(cmdKey))
        )
    }

    func testStartCannotOverwriteShortcutSavedAfterContainerConstruction() async throws {
        var initialPreferences = AppPreferences()
        let oldShortcut = KeyboardShortcut(
            keyCode: 1,
            carbonModifiers: UInt32(optionKey)
        )
        let newShortcut = KeyboardShortcut(
            keyCode: 0,
            carbonModifiers: UInt32(cmdKey)
        )
        initialPreferences.globalShortcut = oldShortcut
        let preferences = StaleReadPreferencesStore(initialPreferences)
        let shortcut = FakeSettingsShortcutRegistrar()
        let container = await ApplicationContainer.make(
            preferencesStore: preferences,
            credentialStore: MemoryCredentialStore(),
            transport: RecordingHTTPTransport(responses: []),
            launchAtLogin: FakeLaunchAtLoginController(),
            shortcutRegistrar: shortcut,
            clipboardSource: EmptyInputSource(),
            installApplicationMenu: false
        )
        defer { container.stop() }
        container.settingsViewModel.globalShortcut = newShortcut
        try await container.settingsViewModel.save()
        await preferences.returnOnce(initialPreferences)

        container.start()

        XCTAssertEqual(shortcut.registerValues, [newShortcut, newShortcut])
        XCTAssertEqual(shortcut.registeredShortcut, newShortcut)
    }

    func testTranslationPopoverHasNoPromptPresetControl() {
        let session = TranslationSession(
            coordinator: TranslationCoordinator(providers: []),
            promptPresetID: .technologyAndRnD
        )
        let host = NSHostingView(
            rootView: TranslationView(
                session: session,
                appearance: ProviderAppearance(llmBrand: .genericAI),
                focusController: TranslationInputFocusController()
            )
        )
        host.frame = NSRect(x: 0, y: 0, width: 370, height: 430)
        let window = NSWindow(
            contentRect: host.bounds,
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        XCTAssertFalse(allSubviews(of: host).contains { $0 is NSPopUpButton })
    }

    private func makeModel(
        credentials: MemoryCredentialStore = MemoryCredentialStore(),
        connectionTester: any ProviderConnectionTesting = RecordingConnectionTester()
    ) async -> SettingsViewModel {
        await SettingsViewModel.make(
            preferencesStore: MemoryPreferencesStore(),
            credentialStore: credentials,
            launchAtLogin: FakeLaunchAtLoginController(),
            shortcutRegistrar: FakeSettingsShortcutRegistrar(),
            shortcutAction: {},
            connectionTester: connectionTester,
            providerAppearance: ProviderAppearance(llmBrand: .genericAI),
            session: nil
        )
    }

    private func makeRollbackFailureModel() async -> SettingsViewModel {
        let credentials = MemoryCredentialStore(values: [
            .googleAPIKey: "old-google",
            .llmAPIKey: "old-llm",
        ])
        credentials.failNext(.write(.llmAPIKey), timing: .afterMutation)
        credentials.failNext(.write(.llmAPIKey), timing: .beforeMutation)
        let model = await makeModel(credentials: credentials)
        model.googleAPIKey = "new-google"
        model.llmBaseURL = "https://api.example.com/v1"
        model.llmAPIKey = "new-llm"
        model.llmModel = "new-model"
        return model
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(allSubviews(of:))
    }

}

private struct EmptyInputSource: InputSource {
    let id = InputSourceID.clipboard

    func read() async throws -> SourceText? {
        nil
    }
}

private actor StaleReadPreferencesStore: PreferencesStoring {
    private var value: AppPreferences
    private var staleValue: AppPreferences?

    init(_ value: AppPreferences) {
        self.value = value
    }

    func load() -> AppPreferences {
        guard let staleValue else { return value }
        self.staleValue = nil
        return staleValue
    }

    func save(_ preferences: AppPreferences) {
        value = preferences
    }

    func returnOnce(_ preferences: AppPreferences) {
        staleValue = preferences
    }
}
