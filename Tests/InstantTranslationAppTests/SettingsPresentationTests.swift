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
        let originalWindow = try XCTUnwrap(controller.window)
        XCTAssertFalse(originalWindow.isReleasedWhenClosed)

        controller.showSettings(nil)
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

    func testApplicationMenuRoutesSettingsAndRetainsQuitCommand() async throws {
        let application = NSApplication.shared
        let previousMenu = application.mainMenu
        defer { application.mainMenu = previousMenu }
        var activationCount = 0
        let controller = SettingsWindowController(
            model: await makeModel(),
            notificationCenter: NotificationCenter(),
            activateApplication: { activationCount += 1 }
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
            clipboardSource: EmptyInputSource()
        )

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
