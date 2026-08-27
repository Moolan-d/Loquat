import XCTest
import InstantTranslationCore
import InstantTranslationFeature
import InstantTranslationInfrastructure
@testable import InstantTranslationApp

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testConstructionDefersCredentialReadsUntilExplicitLoad() async {
        let credentials = MemoryCredentialStore(values: [
            .googleAPIKey: "stored-google",
            .llmAPIKey: "stored-llm",
        ])

        let model = await SettingsViewModel.make(
            preferencesStore: MemoryPreferencesStore(),
            credentialStore: credentials,
            launchAtLogin: FakeLaunchAtLoginController(),
            shortcutRegistrar: FakeSettingsShortcutRegistrar(),
            shortcutAction: {},
            connectionTester: RecordingConnectionTester(),
            providerAppearance: ProviderAppearance(llmBrand: .genericAI),
            session: nil
        )

        XCTAssertEqual(credentials.readCallCount, 0)
        XCTAssertEqual(model.credentialAccessState, .notLoaded)
        XCTAssertEqual(model.googleAPIKey, "")
        XCTAssertEqual(model.llmAPIKey, "")

        model.loadCredentials()

        XCTAssertEqual(credentials.readCallCount, 2)
        XCTAssertEqual(model.credentialAccessState, .loaded)
        XCTAssertEqual(model.googleAPIKey, "stored-google")
        XCTAssertEqual(model.llmAPIKey, "stored-llm")
    }

    func testCredentialReadFailuresRemainUnavailableAndBlockSaveBeforeMutation() async {
        let failingKeys: [[CredentialKey]] = [
            [.googleAPIKey],
            [.llmAPIKey],
            [.googleAPIKey, .llmAPIKey],
        ]

        for keys in failingKeys {
            let preferences = MemoryPreferencesStore()
            let credentials = MemoryCredentialStore(values: [
                .googleAPIKey: "existing-google-secret",
                .llmAPIKey: "existing-llm-secret",
            ])
            keys.forEach(credentials.failNextRead)
            let launch = FakeLaunchAtLoginController()
            let shortcut = FakeSettingsShortcutRegistrar()

            let model = await makeModel(
                preferences: preferences,
                credentials: credentials,
                launch: launch,
                shortcut: shortcut
            )

            XCTAssertEqual(model.credentialAccessState, .unavailable)
            XCTAssertEqual(model.googleAPIKey, "")
            XCTAssertEqual(model.llmAPIKey, "")
            model.translateClipboardOnShortcut = true

            do {
                try await model.save()
                XCTFail("Expected unavailable credentials to block save")
            } catch {
                XCTAssertEqual(error as? SettingsSaveError, .credentialsUnavailable)
                let publicText = String(describing: error) + (model.saveError ?? "")
                XCTAssertFalse(publicText.contains("existing-google-secret"))
                XCTAssertFalse(publicText.contains("existing-llm-secret"))
            }

            XCTAssertEqual(credentials.stored(.googleAPIKey), "existing-google-secret")
            XCTAssertEqual(credentials.stored(.llmAPIKey), "existing-llm-secret")
            XCTAssertTrue(credentials.operations.isEmpty)
            let saveCallCount = await preferences.saveCallCount
            XCTAssertEqual(saveCallCount, 0)
            XCTAssertTrue(launch.setValues.isEmpty)
            XCTAssertTrue(shortcut.registerValues.isEmpty)
        }
    }

    func testExplicitCredentialReloadAtomicallyRestoresValuesAndAllowsSave() async throws {
        let credentials = MemoryCredentialStore(values: [
            .googleAPIKey: "restored-google",
            .llmAPIKey: "restored-llm",
        ])
        credentials.failNextRead(.googleAPIKey)
        credentials.failNextRead(.llmAPIKey)
        let model = await makeModel(credentials: credentials)
        XCTAssertEqual(model.credentialAccessState, .unavailable)

        model.loadCredentials()

        XCTAssertEqual(model.credentialAccessState, .loaded)
        XCTAssertEqual(model.googleAPIKey, "restored-google")
        XCTAssertEqual(model.llmAPIKey, "restored-llm")
        model.llmBaseURL = "https://api.example.com/v1"
        model.llmModel = "restored-model"
        try await model.save()
        XCTAssertEqual(model.saveState, .saved)
    }

    func testCredentialSnapshotReadFailureMarksUnavailableUntilExplicitReload() async {
        let preferences = MemoryPreferencesStore()
        let credentials = MemoryCredentialStore(values: [
            .googleAPIKey: "stored-google",
            .llmAPIKey: "stored-llm",
        ])
        let launch = FakeLaunchAtLoginController()
        let shortcut = FakeSettingsShortcutRegistrar()
        let model = await makeModel(
            preferences: preferences,
            credentials: credentials,
            launch: launch,
            shortcut: shortcut
        )
        credentials.failNextRead(.googleAPIKey)
        model.translateClipboardOnShortcut = true
        model.llmBaseURL = "https://api.example.com/v1"
        model.llmModel = "stored-model"

        do {
            try await model.save()
            XCTFail("Expected credential snapshot read to fail")
        } catch {
            XCTAssertEqual(error as? SettingsSaveError, .credentialsUnavailable)
        }

        XCTAssertEqual(model.credentialAccessState, .unavailable)
        XCTAssertTrue(credentials.operations.isEmpty)
        let saveCallCount = await preferences.saveCallCount
        XCTAssertEqual(saveCallCount, 0)
        XCTAssertTrue(launch.setValues.isEmpty)
        XCTAssertTrue(shortcut.registerValues.isEmpty)

        model.loadCredentials()

        XCTAssertEqual(model.credentialAccessState, .loaded)
        XCTAssertEqual(model.googleAPIKey, "stored-google")
        XCTAssertEqual(model.llmAPIKey, "stored-llm")
    }

    func testOverlappingSaveIsRejectedWithoutStartingSecondTransaction() async throws {
        let preferences = SuspendingPreferencesStore()
        let credentials = MemoryCredentialStore()
        let launch = FakeLaunchAtLoginController()
        let shortcut = FakeSettingsShortcutRegistrar()
        let model = await SettingsViewModel.make(
            preferencesStore: preferences,
            credentialStore: credentials,
            launchAtLogin: launch,
            shortcutRegistrar: shortcut,
            shortcutAction: {},
            connectionTester: RecordingConnectionTester(),
            providerAppearance: ProviderAppearance(llmBrand: .genericAI),
            session: nil
        )
        model.loadCredentials()
        model.launchAtLogin = true
        model.globalShortcut = Self.newShortcut
        model.googleAPIKey = "google"
        await preferences.suspendNextLoad()

        let firstSave = Task { try await model.save() }
        await preferences.waitUntilLoadSuspends()
        XCTAssertEqual(model.saveState, .saving)

        do {
            try await model.save()
            XCTFail("Expected overlapping save to be rejected")
        } catch {
            XCTAssertEqual(error as? SettingsSaveError, .saveInProgress)
            XCTAssertEqual(model.saveState, .saving)
        }

        XCTAssertTrue(credentials.operations.isEmpty)
        XCTAssertTrue(launch.setValues.isEmpty)
        XCTAssertTrue(shortcut.registerValues.isEmpty)
        await preferences.resumeLoad()
        try await firstSave.value

        let saveCallCount = await preferences.saveCallCount
        XCTAssertEqual(saveCallCount, 1)
        XCTAssertEqual(credentials.operations.count, 2)
        XCTAssertEqual(launch.setValues, [true])
        XCTAssertEqual(shortcut.registerValues, [Self.newShortcut])
        XCTAssertEqual(model.saveState, .saved)
        XCTAssertTrue(model.launchAtLogin)
        XCTAssertEqual(model.globalShortcut, Self.newShortcut)
        XCTAssertEqual(model.googleAPIKey, "google")
        let stored = await preferences.stored()
        XCTAssertTrue(stored.launchAtLogin)
        XCTAssertEqual(stored.globalShortcut, Self.newShortcut)
        XCTAssertEqual(credentials.stored(.googleAPIKey), "google")
        XCTAssertTrue(launch.status.isRegistered)
        XCTAssertEqual(shortcut.registeredShortcut, Self.newShortcut)
    }

    func testRejectedOverlappingSaveCannotOverrideFirstSaveRollbackState() async throws {
        let oldPreferences = AppPreferences()
        let preferences = SuspendingPreferencesStore(oldPreferences)
        let credentials = MemoryCredentialStore(values: [
            .googleAPIKey: "old-google",
            .llmAPIKey: "old-llm",
        ])
        let launch = FakeLaunchAtLoginController()
        let shortcut = FakeSettingsShortcutRegistrar()
        let model = await SettingsViewModel.make(
            preferencesStore: preferences,
            credentialStore: credentials,
            launchAtLogin: launch,
            shortcutRegistrar: shortcut,
            shortcutAction: {},
            connectionTester: RecordingConnectionTester(),
            providerAppearance: ProviderAppearance(llmBrand: .genericAI),
            session: nil
        )
        model.loadCredentials()
        model.launchAtLogin = true
        model.globalShortcut = Self.newShortcut
        model.googleAPIKey = "new-google"
        model.llmBaseURL = "https://api.example.com/v1"
        model.llmAPIKey = "new-llm"
        model.llmModel = "new-model"
        await preferences.suspendNextSave(failure: .afterMutation)

        let firstSave = Task { try await model.save() }
        await preferences.waitUntilSaveSuspends()
        do {
            try await model.save()
            XCTFail("Expected overlapping save to be rejected")
        } catch {
            XCTAssertEqual(error as? SettingsSaveError, .saveInProgress)
            XCTAssertEqual(model.saveState, .saving)
        }

        await preferences.resumeSave()
        do {
            try await firstSave.value
            XCTFail("Expected first save to fail")
        } catch {
            XCTAssertEqual(error as? SettingsSaveError, .persistenceFailed)
        }

        XCTAssertEqual(model.saveState, .failed)
        let storedPreferences = await preferences.stored()
        XCTAssertEqual(storedPreferences, oldPreferences)
        XCTAssertEqual(credentials.stored(.googleAPIKey), "old-google")
        XCTAssertEqual(credentials.stored(.llmAPIKey), "old-llm")
        XCTAssertFalse(launch.isEnabled)
        XCTAssertNil(shortcut.registeredShortcut)
    }

    func testLaunchAtLoginControllerReflectsAndMutatesInjectedMainAppService() throws {
        let service = FakeLaunchAtLoginService()
        let controller = LaunchAtLoginController(service: service)

        XCTAssertFalse(controller.isEnabled)

        try controller.setEnabled(true)
        XCTAssertTrue(controller.isEnabled)
        XCTAssertEqual(service.registerCallCount, 1)

        try controller.setEnabled(false)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(service.unregisterCallCount, 1)
    }

    func testLaunchAtLoginControllerUnregistersRequiresApprovalService() throws {
        let service = FakeLaunchAtLoginService(status: .requiresApproval)
        let controller = LaunchAtLoginController(service: service)

        XCTAssertEqual(controller.status, .requiresApproval)

        try controller.setEnabled(false)

        XCTAssertEqual(service.status, .notRegistered)
        XCTAssertEqual(service.unregisterCallCount, 1)
    }

    func testLaunchAtLoginControllerPreservesEveryServiceStatus() {
        let statuses: [LaunchAtLoginStatus] = [
            .notRegistered,
            .enabled,
            .requiresApproval,
            .notFound,
        ]

        for status in statuses {
            let controller = LaunchAtLoginController(
                service: FakeLaunchAtLoginService(status: status)
            )
            XCTAssertEqual(controller.status, status)
        }
    }

    func testSavesSecretsToCredentialStoreAndNotPreferences() async throws {
        let preferences = MemoryPreferencesStore()
        let credentials = MemoryCredentialStore()
        let model = await SettingsViewModel.make(
            preferencesStore: preferences,
            credentialStore: credentials,
            launchAtLogin: FakeLaunchAtLoginController(),
            shortcutRegistrar: FakeSettingsShortcutRegistrar(),
            shortcutAction: {},
            connectionTester: RecordingConnectionTester(),
            providerAppearance: ProviderAppearance(llmBrand: .genericAI),
            session: nil
        )
        model.loadCredentials()
        model.googleAPIKey = "google-secret"
        model.llmAPIKey = "llm-secret"
        model.llmBaseURL = "https://api.openai.com/v1"
        model.llmModel = "gpt-5-mini"

        try await model.save()

        XCTAssertEqual(credentials.stored(.googleAPIKey), "google-secret")
        XCTAssertEqual(credentials.stored(.llmAPIKey), "llm-secret")
        let storedPreferences = await preferences.load()
        XCTAssertTrue(storedPreferences.googleCredentialConfigured)
        XCTAssertTrue(storedPreferences.llmCredentialConfigured)
        let encodedPreferences = String(
            data: try JSONEncoder().encode(storedPreferences),
            encoding: .utf8
        )
        XCTAssertFalse(encodedPreferences?.contains("google-secret") ?? true)
        XCTAssertFalse(encodedPreferences?.contains("llm-secret") ?? true)
    }

    func testRestoresEachPromptIndependently() async {
        let model = await SettingsViewModel.make(
            preferencesStore: MemoryPreferencesStore(),
            credentialStore: MemoryCredentialStore(),
            launchAtLogin: FakeLaunchAtLoginController(),
            shortcutRegistrar: FakeSettingsShortcutRegistrar(),
            shortcutAction: {},
            connectionTester: RecordingConnectionTester(),
            providerAppearance: ProviderAppearance(llmBrand: .genericAI),
            session: nil
        )
        model.generalPrompt = "changed general"
        model.technologyAndRnDPrompt = "changed tech"

        model.restoreGeneralPrompt()

        XCTAssertEqual(model.generalPrompt, DefaultPrompts.general)
        XCTAssertEqual(model.technologyAndRnDPrompt, "changed tech")

        model.generalPrompt = "changed again"
        model.restoreTechnologyAndRnDPrompt()

        XCTAssertEqual(model.generalPrompt, "changed again")
        XCTAssertEqual(model.technologyAndRnDPrompt, DefaultPrompts.technologyAndRnD)
    }

    func testMakeUsesActualLaunchStateInsteadOfStalePreference() async {
        var stored = AppPreferences()
        stored.launchAtLogin = false

        let model = await makeModel(
            preferences: MemoryPreferencesStore(stored),
            launch: FakeLaunchAtLoginController(isEnabled: true)
        )

        XCTAssertTrue(model.launchAtLogin)
    }

    func testSettingsTreatsRequiresApprovalAsRegisteredAndCanDisableIt() async throws {
        let launch = FakeLaunchAtLoginController(status: .requiresApproval)
        let model = await makeModel(launch: launch)

        XCTAssertTrue(model.launchAtLogin)

        model.launchAtLogin = false
        try await model.save()

        XCTAssertEqual(launch.setValues, [false])
        XCTAssertEqual(launch.status, .notRegistered)
    }

    func testInvalidRemoteHTTPAndIncompleteLLMConfigurationFailBeforeMutation() async {
        for invalidConfiguration in [
            ("http://api.example.com/v1", "token", "model"),
            ("https://api.example.com/v1", "token", ""),
            ("https://api.example.com/v1", "", "model"),
        ] {
            let preferences = MemoryPreferencesStore()
            let credentials = MemoryCredentialStore()
            let launch = FakeLaunchAtLoginController()
            let shortcut = FakeSettingsShortcutRegistrar()
            let model = await makeModel(
                preferences: preferences,
                credentials: credentials,
                launch: launch,
                shortcut: shortcut
            )
            model.launchAtLogin = true
            model.globalShortcut = Self.newShortcut
            model.googleAPIKey = " google-secret "
            model.llmBaseURL = invalidConfiguration.0
            model.llmAPIKey = invalidConfiguration.1
            model.llmModel = invalidConfiguration.2

            do {
                try await model.save()
                XCTFail("Expected invalid configuration to fail")
            } catch {
                XCTAssertEqual(model.saveState, .failed)
                XCTAssertFalse(String(describing: error).contains("google-secret"))
                XCTAssertFalse(String(describing: error).contains(invalidConfiguration.0))
            }

            let saveCallCount = await preferences.saveCallCount
            XCTAssertEqual(saveCallCount, 0)
            XCTAssertTrue(credentials.operations.isEmpty)
            XCTAssertTrue(launch.setValues.isEmpty)
            XCTAssertTrue(shortcut.registerValues.isEmpty)
        }
    }

    /// OpenRouter 有兜底模型，Model 因此是可选项；留空要能存下来，且存的是空值——
    /// 兜底发生在请求时，不落盘，slug 变了才能靠发版修好。
    func testOpenRouterAcceptsBlankModelAndPersistsItEmpty() async throws {
        let preferences = MemoryPreferencesStore()
        let credentials = MemoryCredentialStore()
        let model = await makeModel(preferences: preferences, credentials: credentials)
        model.llmBaseURL = "https://openrouter.ai/api/v1"
        model.llmAPIKey = "llm-secret"
        model.llmModel = ""

        try await model.save()

        XCTAssertEqual(model.saveState, .saved)
        let saved = await preferences.load()
        XCTAssertEqual(saved.llmBaseURL, "https://openrouter.ai/api/v1")
        XCTAssertEqual(saved.llmModel, "")
    }

    func testBlankModelPlaceholderAnnouncesTheFallbackOnlyWhereItApplies() async {
        let model = await makeModel()

        model.llmBaseURL = "https://openrouter.ai/api/v1"
        XCTAssertEqual(model.llmModelPlaceholder, "openrouter/free")

        model.llmBaseURL = "https://api.openai.com/v1"
        XCTAssertEqual(model.llmModelPlaceholder, "Model")

        model.llmBaseURL = ""
        XCTAssertEqual(model.llmModelPlaceholder, "Model")
    }

    func testSaveTrimsConfigurationAndCoordinatesEveryConsumer() async throws {
        let preferences = MemoryPreferencesStore()
        let credentials = MemoryCredentialStore()
        let launch = FakeLaunchAtLoginController()
        let shortcut = FakeSettingsShortcutRegistrar()
        let appearance = ProviderAppearance(llmBrand: .genericAI)
        let session = TranslationSession(
            coordinator: TranslationCoordinator(providers: []),
            promptPresetID: .general
        )
        let model = await makeModel(
            preferences: preferences,
            credentials: credentials,
            launch: launch,
            shortcut: shortcut,
            appearance: appearance,
            session: session
        )
        model.launchAtLogin = true
        model.globalShortcut = Self.newShortcut
        model.translateClipboardOnShortcut = true
        model.googleAPIKey = " google-key "
        model.llmBaseURL = " https://api.openai.com/v1/ "
        model.llmAPIKey = " llm-key "
        model.llmModel = " gpt-5-mini "
        model.generalPrompt = " general prompt "
        model.technologyAndRnDPrompt = " tech prompt "
        model.defaultPromptPresetID = .technologyAndRnD

        try await model.save()

        let stored = await preferences.load()
        XCTAssertTrue(stored.launchAtLogin)
        XCTAssertEqual(stored.globalShortcut, Self.newShortcut)
        XCTAssertTrue(stored.translateClipboardOnShortcut)
        XCTAssertEqual(stored.llmBaseURL, "https://api.openai.com/v1")
        XCTAssertEqual(stored.llmModel, "gpt-5-mini")
        XCTAssertEqual(stored.generalPrompt, "general prompt")
        XCTAssertEqual(stored.technologyAndRnDPrompt, "tech prompt")
        XCTAssertEqual(credentials.stored(.googleAPIKey), "google-key")
        XCTAssertEqual(credentials.stored(.llmAPIKey), "llm-key")
        XCTAssertTrue(launch.isEnabled)
        XCTAssertEqual(shortcut.registeredShortcut, Self.newShortcut)
        XCTAssertEqual(session.promptPresetID, .technologyAndRnD)
        XCTAssertEqual(appearance.llmBrand, .openAI)
        XCTAssertEqual(model.saveState, .saved)
        XCTAssertNil(model.saveError)
    }

    func testClearingShortcutAlsoDisablesClipboardOnShortcutOnSave() async throws {
        let preferences = MemoryPreferencesStore()
        let model = await makeModel(preferences: preferences)

        model.globalShortcut = Self.newShortcut
        model.translateClipboardOnShortcut = true
        try await model.save()
        var stored = await preferences.load()
        XCTAssertTrue(stored.translateClipboardOnShortcut)

        // 清空快捷键后再次保存，剪贴板开关被强制关闭，不把失效值写回磁盘。
        model.globalShortcut = nil
        try await model.save()
        stored = await preferences.load()
        XCTAssertFalse(stored.translateClipboardOnShortcut)
        XCTAssertFalse(model.translateClipboardOnShortcut)
    }

    func testAllowsHTTPForLoopbackLLMEndpoint() async throws {
        let preferences = MemoryPreferencesStore()
        let model = await makeModel(preferences: preferences)
        model.llmBaseURL = " http://127.0.0.1:11434/v1/ "
        model.llmAPIKey = " local-key "
        model.llmModel = " local-model "

        try await model.save()

        let stored = await preferences.load()
        XCTAssertEqual(stored.llmBaseURL, "http://127.0.0.1:11434/v1")
    }

    func testExplicitConnectionTestsCallOnlySelectedProviderAndNeverRunOnEditOrSave() async throws {
        let tester = RecordingConnectionTester()
        let model = await makeModel(connectionTester: tester)
        model.googleAPIKey = " google-key "
        model.llmBaseURL = " https://api.example.com/v1 "
        model.llmAPIKey = " llm-key "
        model.llmModel = " model-name "
        model.generalPrompt = " selected prompt "
        model.defaultPromptPresetID = .general

        try await model.save()
        var googleKeys = await tester.googleKeys
        var llmConfigurations = await tester.llmConfigurations
        XCTAssertEqual(googleKeys.count, 0)
        XCTAssertEqual(llmConfigurations.count, 0)

        await model.testGoogleConnection()
        googleKeys = await tester.googleKeys
        llmConfigurations = await tester.llmConfigurations
        XCTAssertEqual(googleKeys, ["google-key"])
        XCTAssertEqual(llmConfigurations.count, 0)

        await model.testLLMConnection()
        googleKeys = await tester.googleKeys
        llmConfigurations = await tester.llmConfigurations
        let configuration = try XCTUnwrap(llmConfigurations.first)
        XCTAssertEqual(googleKeys.count, 1)
        XCTAssertEqual(configuration.baseURL, "https://api.example.com/v1")
        XCTAssertEqual(configuration.apiKey, "llm-key")
        XCTAssertEqual(configuration.model, "model-name")
        XCTAssertEqual(configuration.systemPrompt, "selected prompt")
    }

    func testConnectionValidationDoesNotCallProvider() async {
        let tester = RecordingConnectionTester()
        let model = await makeModel(connectionTester: tester)

        await model.testGoogleConnection()
        XCTAssertEqual(model.googleConnectionState, .failure(.unconfigured))
        let googleKeys = await tester.googleKeys
        XCTAssertEqual(googleKeys.count, 0)

        model.llmBaseURL = "http://remote.example/v1"
        model.llmAPIKey = "secret"
        model.llmModel = "model"
        await model.testLLMConnection()
        XCTAssertEqual(model.llmConnectionState, .failure(.insecureEndpoint))
        let llmConfigurations = await tester.llmConfigurations
        XCTAssertEqual(llmConfigurations.count, 0)
    }

    func testLLMConnectionValidatesOnlyTheSelectedPrompt() async throws {
        let cases: [(PromptPresetID, String, String, String)] = [
            (.general, "general selected", "", "general selected"),
            (.technologyAndRnD, "", "technology selected", "technology selected"),
        ]

        for (preset, general, technology, expectedPrompt) in cases {
            let tester = RecordingConnectionTester()
            let model = await makeModel(connectionTester: tester)
            model.llmBaseURL = "https://api.example.com/v1"
            model.llmAPIKey = "llm-key"
            model.llmModel = "model"
            model.generalPrompt = general
            model.technologyAndRnDPrompt = technology
            model.defaultPromptPresetID = preset

            await model.testLLMConnection()

            let configurations = await tester.llmConfigurations
            let configuration = try XCTUnwrap(configurations.first)
            XCTAssertEqual(configurations.count, 1)
            XCTAssertEqual(configuration.systemPrompt, expectedPrompt)
            XCTAssertEqual(model.llmConnectionState, .success)
        }
    }

    func testStaleOverlappingConnectionCompletionCannotOverwriteNewestState() async {
        let tester = ControlledConnectionTester()
        let model = await makeModel(connectionTester: tester)
        model.googleAPIKey = "first"

        let first = Task { await model.testGoogleConnection() }
        await waitForGoogleCalls(1, tester: tester)
        model.googleAPIKey = "second"
        let second = Task { await model.testGoogleConnection() }
        await waitForGoogleCalls(2, tester: tester)

        await tester.completeGoogle(at: 1, with: .success)
        await second.value
        XCTAssertEqual(model.googleConnectionState, .success)

        await tester.completeGoogle(at: 0, with: .failure(.timedOut))
        await first.value
        XCTAssertEqual(model.googleConnectionState, .success)
    }

    func testStaleOverlappingLLMCompletionCannotOverwriteNewestState() async {
        let tester = ControlledConnectionTester()
        let model = await makeModel(connectionTester: tester)
        model.llmBaseURL = "https://api.example.com/v1"
        model.llmAPIKey = "first"
        model.llmModel = "model"

        let first = Task { await model.testLLMConnection() }
        await waitForLLMCalls(1, tester: tester)
        model.llmAPIKey = "second"
        let second = Task { await model.testLLMConnection() }
        await waitForLLMCalls(2, tester: tester)

        await tester.completeLLM(at: 1, with: .success)
        await second.value
        XCTAssertEqual(model.llmConnectionState, .success)

        await tester.completeLLM(at: 0, with: .failure(.timedOut))
        await first.value
        XCTAssertEqual(model.llmConnectionState, .success)
    }

    func testProviderConnectionTesterSendsOneFixedRequestPerExplicitCall() async throws {
        let googleData = Data(#"{"data":{"translations":[{"translatedText":"测试"}]}}"#.utf8)
        let llmData = Data(
            #"{"choices":[{"message":{"content":"{\"translation\":\"测试\",\"rationale\":\"ok\"}"}}]}"#.utf8
        )
        let transport = RecordingHTTPTransport(responses: [
            HTTPResponse(data: googleData, statusCode: 200),
            HTTPResponse(data: llmData, statusCode: 200),
        ])
        let tester = ProviderConnectionTester(transport: transport)

        let googleState = await tester.testGoogle(apiKey: "google-key")
        let llmState = await tester.testLLM(configuration: .init(
            baseURL: "https://api.example.com/v1",
            apiKey: "llm-key",
            model: "model",
            systemPrompt: "prompt"
        ))

        XCTAssertEqual(googleState, .success)
        XCTAssertEqual(llmState, .success)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "X-Goog-Api-Key"), "google-key")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(String(data: try XCTUnwrap(requests[0].httpBody), encoding: .utf8)?.contains("\"q\":\"test\"") == true)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer llm-key")
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "X-Goog-Api-Key"))
        XCTAssertTrue(String(data: try XCTUnwrap(requests[1].httpBody), encoding: .utf8)?.contains("Text: test") == true)
    }

    func testShortcutFailureRestoresOldRuntimeAndLeavesPersistenceUnchanged() async {
        let context = await makeFailureContext()
        context.shortcut.failNextRegister(.beforeMutation)

        await assertFailedSaveIsCompensated(context)

        XCTAssertEqual(context.shortcut.registeredShortcut, Self.oldShortcut)
        XCTAssertTrue(context.launch.setValues.isEmpty)
    }

    func testRollbackRestoresActualRuntimeShortcutWhenPreferencesHaveDrifted() async {
        var oldPreferences = AppPreferences()
        oldPreferences.globalShortcut = Self.oldShortcut
        let preferences = MemoryPreferencesStore(oldPreferences)
        let launch = FakeLaunchAtLoginController()
        launch.failNextSet(.beforeMutation)
        let shortcut = FakeSettingsShortcutRegistrar(
            registeredShortcut: Self.driftedRuntimeShortcut
        )
        let model = await makeModel(
            preferences: preferences,
            launch: launch,
            shortcut: shortcut
        )
        model.launchAtLogin = true
        model.globalShortcut = Self.newShortcut

        do {
            try await model.save()
            XCTFail("Expected launch-at-login failure")
        } catch {
            XCTAssertEqual(error as? SettingsSaveError, .persistenceFailed)
        }

        XCTAssertEqual(shortcut.registeredShortcut, Self.driftedRuntimeShortcut)
        let stored = await preferences.load()
        XCTAssertEqual(stored.globalShortcut, Self.oldShortcut)
    }

    func testLaunchFailureAfterMutationRestoresShortcutAndLaunchState() async {
        let context = await makeFailureContext()
        context.launch.failNextSet(.afterMutation)

        await assertFailedSaveIsCompensated(context)

        XCTAssertEqual(context.shortcut.registeredShortcut, Self.oldShortcut)
        XCTAssertFalse(context.launch.isEnabled)
        XCTAssertEqual(context.launch.setValues, [true, false])
    }

    func testCredentialFailureRestoresEarlierCredentialAndRuntimeChanges() async {
        let context = await makeFailureContext()
        context.credentials.failNext(.write(.llmAPIKey), timing: .afterMutation)

        await assertFailedSaveIsCompensated(context)

        XCTAssertEqual(context.credentials.stored(.googleAPIKey), "old-google")
        XCTAssertEqual(context.credentials.stored(.llmAPIKey), "old-llm")
        XCTAssertEqual(context.shortcut.registeredShortcut, Self.oldShortcut)
        XCTAssertFalse(context.launch.isEnabled)
    }

    func testCredentialWriteAndDeleteFailuresBeforeAndAfterMutationRestoreAllDomains() async {
        let keys: [CredentialKey] = [.googleAPIKey, .llmAPIKey]
        let timings: [FakeFailureTiming] = [.beforeMutation, .afterMutation]

        for key in keys {
            for deletesCredential in [false, true] {
                for timing in timings {
                    let context = await makeFailureContext()
                    let operation: CredentialOperation
                    if deletesCredential {
                        operation = .delete(key)
                        if key == .googleAPIKey {
                            context.model.googleAPIKey = ""
                        } else if key == .llmAPIKey {
                            context.model.llmBaseURL = ""
                            context.model.llmAPIKey = ""
                            context.model.llmModel = ""
                        }
                    } else {
                        operation = .write(key)
                    }
                    context.credentials.failNext(operation, timing: timing)

                    await assertFailedSaveIsCompensated(context)

                    XCTAssertEqual(context.shortcut.registeredShortcut, Self.oldShortcut)
                    XCTAssertFalse(context.launch.status.isRegistered)
                }
            }
        }
    }

    func testCredentialRollbackFailureReportsNeedsAttentionWithoutLeakingSecrets() async {
        let context = await makeFailureContext()
        context.credentials.failNext(.write(.llmAPIKey), timing: .afterMutation)
        context.credentials.failNext(.write(.llmAPIKey), timing: .beforeMutation)

        do {
            try await context.model.save()
            XCTFail("Expected save failure")
        } catch {
            XCTAssertEqual(error as? SettingsSaveError, .rollbackIncomplete)
            XCTAssertEqual(context.model.saveState, .needsAttention)
            let publicText = String(describing: error) + (context.model.saveError ?? "")
            XCTAssertFalse(publicText.contains("new-llm-secret"))
            XCTAssertFalse(publicText.contains("private.example.com"))
        }

        let storedPreferences = await context.preferences.load()
        XCTAssertEqual(storedPreferences, context.oldPreferences)
        XCTAssertEqual(context.credentials.stored(.googleAPIKey), "old-google")
        XCTAssertEqual(context.credentials.stored(.llmAPIKey), "new-llm-secret")
        XCTAssertEqual(context.shortcut.registeredShortcut, Self.oldShortcut)
        XCTAssertFalse(context.launch.status.isRegistered)
    }

    func testPreferencesFailureAfterMutationRestoresAllPriorState() async {
        let context = await makeFailureContext()
        await context.preferences.failNextSave(.afterMutation)

        await assertFailedSaveIsCompensated(context)

        let stored = await context.preferences.load()
        XCTAssertEqual(stored, context.oldPreferences)
        XCTAssertEqual(context.credentials.stored(.googleAPIKey), "old-google")
        XCTAssertEqual(context.credentials.stored(.llmAPIKey), "old-llm")
        XCTAssertEqual(context.shortcut.registeredShortcut, Self.oldShortcut)
        XCTAssertFalse(context.launch.isEnabled)
        XCTAssertEqual(context.session.promptPresetID, .general)
        XCTAssertEqual(context.appearance.llmBrand, .genericAI)
    }

    func testFailedRollbackReportsNeedsAttentionWithoutLeakingConfiguration() async {
        let context = await makeFailureContext()
        context.shortcut.failNextRegister(.beforeMutation)
        context.shortcut.failNextRegister(.beforeMutation)

        do {
            try await context.model.save()
            XCTFail("Expected save failure")
        } catch {
            XCTAssertEqual(context.model.saveState, .needsAttention)
            let publicText = String(describing: error) + (context.model.saveError ?? "")
            XCTAssertFalse(publicText.contains("new-google-secret"))
            XCTAssertFalse(publicText.contains("private.example.com"))
        }
    }

    private static let oldShortcut = KeyboardShortcut(keyCode: 0, carbonModifiers: 256)
    private static let newShortcut = KeyboardShortcut(keyCode: 1, carbonModifiers: 512)
    private static let driftedRuntimeShortcut = KeyboardShortcut(
        keyCode: 2,
        carbonModifiers: 768
    )

    private func makeModel(
        preferences: MemoryPreferencesStore = MemoryPreferencesStore(),
        credentials: MemoryCredentialStore = MemoryCredentialStore(),
        launch: FakeLaunchAtLoginController = FakeLaunchAtLoginController(),
        shortcut: FakeSettingsShortcutRegistrar = FakeSettingsShortcutRegistrar(),
        connectionTester: any ProviderConnectionTesting = RecordingConnectionTester(),
        appearance: ProviderAppearance = ProviderAppearance(llmBrand: .genericAI),
        session: TranslationSession? = nil
    ) async -> SettingsViewModel {
        let model = await SettingsViewModel.make(
            preferencesStore: preferences,
            credentialStore: credentials,
            launchAtLogin: launch,
            shortcutRegistrar: shortcut,
            shortcutAction: {},
            connectionTester: connectionTester,
            providerAppearance: appearance,
            session: session
        )
        model.loadCredentials()
        return model
    }

    private struct FailureContext {
        let model: SettingsViewModel
        let preferences: MemoryPreferencesStore
        let credentials: MemoryCredentialStore
        let launch: FakeLaunchAtLoginController
        let shortcut: FakeSettingsShortcutRegistrar
        let appearance: ProviderAppearance
        let session: TranslationSession
        let oldPreferences: AppPreferences
    }

    private func makeFailureContext() async -> FailureContext {
        var oldPreferences = AppPreferences()
        oldPreferences.globalShortcut = Self.oldShortcut
        oldPreferences.llmBaseURL = "https://old.example.com/v1"
        oldPreferences.llmModel = "old-model"
        oldPreferences.defaultPromptPresetID = .general
        let preferences = MemoryPreferencesStore(oldPreferences)
        let credentials = MemoryCredentialStore(values: [
            .googleAPIKey: "old-google",
            .llmAPIKey: "old-llm",
        ])
        let launch = FakeLaunchAtLoginController()
        let shortcut = FakeSettingsShortcutRegistrar(registeredShortcut: Self.oldShortcut)
        let appearance = ProviderAppearance(llmBrand: .genericAI)
        let session = TranslationSession(
            coordinator: TranslationCoordinator(providers: []),
            promptPresetID: .general
        )
        let model = await makeModel(
            preferences: preferences,
            credentials: credentials,
            launch: launch,
            shortcut: shortcut,
            appearance: appearance,
            session: session
        )
        model.launchAtLogin = true
        model.globalShortcut = Self.newShortcut
        model.googleAPIKey = "new-google-secret"
        model.llmBaseURL = "https://private.example.com/v1"
        model.llmAPIKey = "new-llm-secret"
        model.llmModel = "new-model"
        model.defaultPromptPresetID = .technologyAndRnD
        return FailureContext(
            model: model,
            preferences: preferences,
            credentials: credentials,
            launch: launch,
            shortcut: shortcut,
            appearance: appearance,
            session: session,
            oldPreferences: oldPreferences
        )
    }

    private func assertFailedSaveIsCompensated(
        _ context: FailureContext,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await context.model.save()
            XCTFail("Expected save failure", file: file, line: line)
        } catch {
            XCTAssertEqual(context.model.saveState, .failed, file: file, line: line)
            XCTAssertNotNil(context.model.saveError, file: file, line: line)
        }
        let storedPreferences = await context.preferences.load()
        XCTAssertEqual(
            storedPreferences,
            context.oldPreferences,
            file: file,
            line: line
        )
        XCTAssertEqual(
            context.credentials.stored(.googleAPIKey),
            "old-google",
            file: file,
            line: line
        )
        XCTAssertEqual(
            context.credentials.stored(.llmAPIKey),
            "old-llm",
            file: file,
            line: line
        )
    }

    private func waitForGoogleCalls(
        _ expected: Int,
        tester: ControlledConnectionTester
    ) async {
        while await tester.googleCallCount() < expected {
            await Task.yield()
        }
    }

    private func waitForLLMCalls(
        _ expected: Int,
        tester: ControlledConnectionTester
    ) async {
        while await tester.llmCallCount() < expected {
            await Task.yield()
        }
    }
}
