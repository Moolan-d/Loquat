import XCTest
import InstantTranslationApp
import InstantTranslationCore
import InstantTranslationFeature
import InstantTranslationInfrastructure
@testable import InstantTranslationDiagnostics

@MainActor
final class DiagnosticsScenarioTests: XCTestCase {
    func testCatalogAndTypedConfigurationsAreClosedAndExact() {
        XCTAssertEqual(
            DiagnosticsScenario.allCases.map(\.rawValue),
            [
                "slow-request", "google-failure", "llm-failure",
                "invalid-credentials", "rate-limited", "offline",
                "google-timeout", "llm-timeout", "malformed-llm",
                "credential-reload", "rollback-incomplete",
            ]
        )

        let googleSuccess = DiagnosticsProviderBehavior.success(
            primaryText: "DIAGNOSTIC_FIXTURE_GOOGLE_TRANSLATION"
        )
        let llmSuccess = DiagnosticsProviderBehavior.success(
            primaryText: "DIAGNOSTIC_FIXTURE_LLM_TRANSLATION"
        )
        let cases: [(DiagnosticsScenario, DiagnosticsScenarioConfiguration)] = [
            (.slowRequest, .init(
                initialInput: "DIAGNOSTIC_FIXTURE_TERM",
                destination: .translationPopover,
                googleBehavior: .pending(
                    primaryText: "DIAGNOSTIC_FIXTURE_GOOGLE_TRANSLATION"
                ),
                llmBehavior: llmSuccess,
                expectedVisibleState: "Google card: loading; LLM card: DIAGNOSTIC_FIXTURE_LLM_TRANSLATION"
            )),
            (.googleFailure, .init(
                initialInput: "DIAGNOSTIC_FIXTURE_TERM",
                destination: .translationPopover,
                googleBehavior: .failure(.server(statusCode: 503)),
                llmBehavior: llmSuccess,
                expectedVisibleState: "Google card: Service error (503).; LLM card: DIAGNOSTIC_FIXTURE_LLM_TRANSLATION"
            )),
            (.llmFailure, .init(
                initialInput: "DIAGNOSTIC_FIXTURE_TERM",
                destination: .translationPopover,
                googleBehavior: googleSuccess,
                llmBehavior: .failure(.server(statusCode: 502)),
                expectedVisibleState: "Google card: DIAGNOSTIC_FIXTURE_GOOGLE_TRANSLATION; LLM card: Service error (502)."
            )),
            (.invalidCredentials, .init(
                initialInput: "DIAGNOSTIC_FIXTURE_TERM",
                destination: .translationPopover,
                googleBehavior: .failure(.invalidCredentials),
                llmBehavior: .failure(.invalidCredentials),
                expectedVisibleState: "Both cards: Check the API key."
            )),
            (.rateLimited, .init(
                initialInput: "DIAGNOSTIC_FIXTURE_TERM",
                destination: .translationPopover,
                googleBehavior: .failure(.rateLimited),
                llmBehavior: .failure(.rateLimited),
                expectedVisibleState: "Both cards: Rate limit reached. Try again later."
            )),
            (.offline, .init(
                initialInput: "DIAGNOSTIC_FIXTURE_TERM",
                destination: .translationPopover,
                googleBehavior: .failure(.networkUnavailable),
                llmBehavior: .failure(.networkUnavailable),
                expectedVisibleState: "Both cards: Network unavailable."
            )),
            (.googleTimeout, .init(
                initialInput: "DIAGNOSTIC_FIXTURE_TERM",
                destination: .translationPopover,
                googleBehavior: .failure(.timedOut),
                llmBehavior: llmSuccess,
                expectedVisibleState: "Google card: Request timed out.; LLM card: DIAGNOSTIC_FIXTURE_LLM_TRANSLATION"
            )),
            (.llmTimeout, .init(
                initialInput: "DIAGNOSTIC_FIXTURE_TERM",
                destination: .translationPopover,
                googleBehavior: googleSuccess,
                llmBehavior: .failure(.timedOut),
                expectedVisibleState: "Google card: DIAGNOSTIC_FIXTURE_GOOGLE_TRANSLATION; LLM card: Request timed out."
            )),
            (.malformedLLM, .init(
                initialInput: "DIAGNOSTIC_FIXTURE_TERM",
                destination: .translationPopover,
                googleBehavior: googleSuccess,
                llmBehavior: .failure(.invalidResponse),
                expectedVisibleState: "Google card: DIAGNOSTIC_FIXTURE_GOOGLE_TRANSLATION; LLM card: The service returned an invalid response."
            )),
            (.credentialReload, .init(
                initialInput: "",
                destination: .settings,
                googleBehavior: googleSuccess,
                llmBehavior: llmSuccess,
                expectedVisibleState: "Settings: credentials unavailable; Reload restores synthetic placeholders."
            )),
            (.rollbackIncomplete, .init(
                initialInput: "",
                destination: .settings,
                googleBehavior: googleSuccess,
                llmBehavior: llmSuccess,
                expectedVisibleState: "Settings save: needs attention after incomplete rollback."
            )),
        ]

        for (scenario, expected) in cases {
            XCTAssertEqual(scenario.configuration, expected, scenario.rawValue)
        }
    }

    func testUnknownArgumentReturnsSafeUsageWithEveryValidName() {
        let result = DiagnosticsScenario.parse("not-a-scenario")

        guard case .failure(let error) = result else {
            return XCTFail("Expected an unknown scenario to fail")
        }
        for name in DiagnosticsScenario.allCases.map(\.rawValue) {
            XCTAssertTrue(error.message.contains(name), name)
        }
        XCTAssertTrue(error.message.contains("usage: InstantTranslationDiagnostics <scenario>"))
        XCTAssertFalse(error.message.localizedCaseInsensitiveContains("api key"))
        XCTAssertFalse(error.message.contains("DIAGNOSTIC_FIXTURE_GOOGLE_KEY"))
        XCTAssertFalse(error.message.contains("DIAGNOSTIC_FIXTURE_LLM_KEY"))
    }

    func testEveryCompositionAvoidsAllLiveIOFactories() async {
        for scenario in DiagnosticsScenario.allCases {
            let audit = DiagnosticsLiveIOAudit()
            let factories = recordingLiveFactories(audit: audit)

            _ = await DiagnosticsDependencies.makeComposition(
                for: scenario,
                liveIOFactories: factories
            )

            XCTAssertEqual(audit.snapshot, .zero, scenario.rawValue)
        }
    }

    func testTranslationScenariosDriveIndependentRealSessionCardStates() async {
        for scenario in DiagnosticsScenario.allCases
        where scenario.configuration.destination == .translationPopover {
            let composition = await DiagnosticsDependencies.makeComposition(for: scenario)
            let expected = expectedProviderBehaviors(for: scenario)

            await waitForState(
                composition.session,
                providerID: .google,
                behavior: expected.google
            )
            await waitForState(
                composition.session,
                providerID: .llm,
                behavior: expected.llm
            )

            assert(
                composition.session.states[.google],
                matches: expected.google,
                providerID: .google,
                scenario: scenario
            )
            assert(
                composition.session.states[.llm],
                matches: expected.llm,
                providerID: .llm,
                scenario: scenario
            )
            XCTAssertEqual(composition.session.input, "DIAGNOSTIC_FIXTURE_TERM")
        }
    }

    func testSlowRequestCompletesOnlyFromExplicitDiagnosticAction() async {
        let composition = await DiagnosticsDependencies.makeComposition(for: .slowRequest)
        await waitForState(
            composition.session,
            providerID: .llm,
            behavior: .success(primaryText: "DIAGNOSTIC_FIXTURE_LLM_TRANSLATION")
        )

        assert(
            composition.session.states[.google],
            matches: .pending(primaryText: "DIAGNOSTIC_FIXTURE_GOOGLE_TRANSLATION"),
            providerID: .google,
            scenario: .slowRequest
        )

        await composition.completeSlowRequest()
        await waitForState(
            composition.session,
            providerID: .google,
            behavior: .success(primaryText: "DIAGNOSTIC_FIXTURE_GOOGLE_TRANSLATION")
        )

        assert(
            composition.session.states[.google],
            matches: .success(primaryText: "DIAGNOSTIC_FIXTURE_GOOGLE_TRANSLATION"),
            providerID: .google,
            scenario: .slowRequest
        )
    }

    func testCredentialReloadStartsUnavailableThenAtomicallyLoadsSyntheticValues() async {
        let composition = await DiagnosticsDependencies.makeComposition(for: .credentialReload)

        XCTAssertEqual(composition.settingsViewModel.credentialAccessState, .unavailable)
        XCTAssertEqual(composition.settingsViewModel.googleAPIKey, "")
        XCTAssertEqual(composition.settingsViewModel.llmAPIKey, "")

        composition.settingsViewModel.reloadCredentials()

        XCTAssertEqual(composition.settingsViewModel.credentialAccessState, .loaded)
        XCTAssertEqual(
            composition.settingsViewModel.googleAPIKey,
            "DIAGNOSTIC_FIXTURE_GOOGLE_KEY"
        )
        XCTAssertEqual(
            composition.settingsViewModel.llmAPIKey,
            "DIAGNOSTIC_FIXTURE_LLM_KEY"
        )
    }

    func testRollbackIncompletePublishesNeedsAttentionUsingOnlyMemoryPreferences() async {
        let audit = DiagnosticsLiveIOAudit()
        let composition = await DiagnosticsDependencies.makeComposition(
            for: .rollbackIncomplete,
            liveIOFactories: recordingLiveFactories(audit: audit)
        )

        XCTAssertEqual(composition.settingsViewModel.saveState, .needsAttention)
        XCTAssertEqual(
            composition.settingsViewModel.saveError,
            SettingsSaveError.rollbackIncomplete.localizedDescription
        )
        let saveAttemptCount = await composition.preferencesStore.saveAttemptCount
        XCTAssertEqual(saveAttemptCount, 2)
        XCTAssertEqual(audit.snapshot, .zero)
    }

    func testProviderFailuresUseTheSameErrorsForRealCardsAndSettingsConnectionPolicy() async {
        for scenario in DiagnosticsScenario.allCases {
            let composition = await DiagnosticsDependencies.makeComposition(for: scenario)
            let configuration = scenario.configuration

            if case .failure(let expectedError) = configuration.googleBehavior {
                await composition.settingsViewModel.testGoogleConnection()
                XCTAssertEqual(
                    composition.settingsViewModel.googleConnectionState,
                    .failure(expectedError),
                    scenario.rawValue
                )
            }
            if case .failure(let expectedError) = configuration.llmBehavior {
                await composition.settingsViewModel.testLLMConnection()
                XCTAssertEqual(
                    composition.settingsViewModel.llmConnectionState,
                    .failure(expectedError),
                    scenario.rawValue
                )
            }
        }
    }

    private func recordingLiveFactories(
        audit: DiagnosticsLiveIOAudit
    ) -> DiagnosticsLiveIOFactories {
        DiagnosticsLiveIOFactories(
            makeHTTPTransport: {
                audit.record(.urlSessionHTTPTransport)
                return TestHTTPTransport()
            },
            makeCredentialStore: {
                audit.record(.keychainCredentialStore)
                return TestCredentialStore()
            },
            makePreferencesStore: {
                audit.record(.userDefaultsPreferencesStore)
                return TestPreferencesStore()
            },
            makeClipboardSource: {
                audit.record(.clipboardInputSource)
                return TestInputSource()
            }
        )
    }

    private func expectedProviderBehaviors(
        for scenario: DiagnosticsScenario
    ) -> (google: DiagnosticsProviderBehavior, llm: DiagnosticsProviderBehavior) {
        let googleSuccess = DiagnosticsProviderBehavior.success(
            primaryText: "DIAGNOSTIC_FIXTURE_GOOGLE_TRANSLATION"
        )
        let llmSuccess = DiagnosticsProviderBehavior.success(
            primaryText: "DIAGNOSTIC_FIXTURE_LLM_TRANSLATION"
        )
        switch scenario {
        case .slowRequest:
            return (.pending(primaryText: "DIAGNOSTIC_FIXTURE_GOOGLE_TRANSLATION"), llmSuccess)
        case .googleFailure:
            return (.failure(.server(statusCode: 503)), llmSuccess)
        case .llmFailure:
            return (googleSuccess, .failure(.server(statusCode: 502)))
        case .invalidCredentials:
            return (.failure(.invalidCredentials), .failure(.invalidCredentials))
        case .rateLimited:
            return (.failure(.rateLimited), .failure(.rateLimited))
        case .offline:
            return (.failure(.networkUnavailable), .failure(.networkUnavailable))
        case .googleTimeout:
            return (.failure(.timedOut), llmSuccess)
        case .llmTimeout:
            return (googleSuccess, .failure(.timedOut))
        case .malformedLLM:
            return (googleSuccess, .failure(.invalidResponse))
        case .credentialReload, .rollbackIncomplete:
            XCTFail("Settings scenario has no translation routing expectation")
            return (googleSuccess, llmSuccess)
        }
    }

    private func waitForState(
        _ session: TranslationSession,
        providerID: ProviderID,
        behavior: DiagnosticsProviderBehavior
    ) async {
        if case .pending = behavior { return }
        for _ in 0..<1_000 {
            if state(session.states[providerID], matches: behavior, providerID: providerID) {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(providerID.rawValue)")
    }

    private func assert(
        _ state: ProviderCardState?,
        matches behavior: DiagnosticsProviderBehavior,
        providerID: ProviderID,
        scenario: DiagnosticsScenario
    ) {
        XCTAssertTrue(
            self.state(state, matches: behavior, providerID: providerID),
            "\(scenario.rawValue) routed the wrong behavior to \(providerID.rawValue): \(String(describing: state))"
        )
    }

    private func state(
        _ state: ProviderCardState?,
        matches behavior: DiagnosticsProviderBehavior,
        providerID: ProviderID
    ) -> Bool {
        switch (state, behavior) {
        case (.loading, .pending):
            true
        case let (.success(result), .success(primaryText)):
            result.providerID == providerID && result.primaryText == primaryText
        case let (.failure(_, actualError), .failure(expectedError)):
            actualError == expectedError
        default:
            false
        }
    }
}

private struct TestHTTPTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        XCTFail("Live HTTP factory output must never be used")
        throw TranslationProviderError.networkUnavailable
    }
}

private final class TestCredentialStore: CredentialStoring, @unchecked Sendable {
    func read(_ key: CredentialKey) throws -> String? { nil }
    func write(_ value: String, for key: CredentialKey) throws {}
    func delete(_ key: CredentialKey) throws {}
}

private actor TestPreferencesStore: PreferencesStoring {
    func load() -> AppPreferences { AppPreferences() }
    func save(_ preferences: AppPreferences) {}
}

private struct TestInputSource: InputSource {
    let id = InputSourceID.clipboard
    func read() async throws -> SourceText? { nil }
}
