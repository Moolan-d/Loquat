import Foundation
import InstantTranslationCore

public enum DiagnosticsScenario: String, CaseIterable, Sendable {
    case slowRequest = "slow-request"
    case googleFailure = "google-failure"
    case llmFailure = "llm-failure"
    case invalidCredentials = "invalid-credentials"
    case rateLimited = "rate-limited"
    case offline
    case googleTimeout = "google-timeout"
    case llmTimeout = "llm-timeout"
    case malformedLLM = "malformed-llm"
    case credentialReload = "credential-reload"
    case rollbackIncomplete = "rollback-incomplete"

    public static func parse(_ argument: String) -> Result<Self, DiagnosticsUsageError> {
        guard let scenario = Self(rawValue: argument) else {
            return .failure(DiagnosticsUsageError())
        }
        return .success(scenario)
    }

    public var configuration: DiagnosticsScenarioConfiguration {
        let googleSuccess = DiagnosticsProviderBehavior.success(
            primaryText: DiagnosticsFixtures.googleTranslation
        )
        let llmSuccess = DiagnosticsProviderBehavior.success(
            primaryText: DiagnosticsFixtures.llmTranslation
        )
        switch self {
        case .slowRequest:
            return .init(
                initialInput: DiagnosticsFixtures.term,
                destination: .translationPopover,
                googleBehavior: .pending(primaryText: DiagnosticsFixtures.googleTranslation),
                llmBehavior: llmSuccess,
                expectedVisibleState: "Google card: loading; LLM card: DIAGNOSTIC_FIXTURE_LLM_TRANSLATION"
            )
        case .googleFailure:
            return .init(
                initialInput: DiagnosticsFixtures.term,
                destination: .translationPopover,
                googleBehavior: .failure(.server(statusCode: 503)),
                llmBehavior: llmSuccess,
                expectedVisibleState: "Google card: Service error (503).; LLM card: DIAGNOSTIC_FIXTURE_LLM_TRANSLATION"
            )
        case .llmFailure:
            return .init(
                initialInput: DiagnosticsFixtures.term,
                destination: .translationPopover,
                googleBehavior: googleSuccess,
                llmBehavior: .failure(.server(statusCode: 502)),
                expectedVisibleState: "Google card: DIAGNOSTIC_FIXTURE_GOOGLE_TRANSLATION; LLM card: Service error (502)."
            )
        case .invalidCredentials:
            return .init(
                initialInput: DiagnosticsFixtures.term,
                destination: .translationPopover,
                googleBehavior: .failure(.invalidCredentials),
                llmBehavior: .failure(.invalidCredentials),
                expectedVisibleState: "Both cards: Check the API key."
            )
        case .rateLimited:
            return .init(
                initialInput: DiagnosticsFixtures.term,
                destination: .translationPopover,
                googleBehavior: .failure(.rateLimited),
                llmBehavior: .failure(.rateLimited),
                expectedVisibleState: "Both cards: Rate limit reached. Try again later."
            )
        case .offline:
            return .init(
                initialInput: DiagnosticsFixtures.term,
                destination: .translationPopover,
                googleBehavior: .failure(.networkUnavailable),
                llmBehavior: .failure(.networkUnavailable),
                expectedVisibleState: "Both cards: Network unavailable."
            )
        case .googleTimeout:
            return .init(
                initialInput: DiagnosticsFixtures.term,
                destination: .translationPopover,
                googleBehavior: .failure(.timedOut),
                llmBehavior: llmSuccess,
                expectedVisibleState: "Google card: Request timed out.; LLM card: DIAGNOSTIC_FIXTURE_LLM_TRANSLATION"
            )
        case .llmTimeout:
            return .init(
                initialInput: DiagnosticsFixtures.term,
                destination: .translationPopover,
                googleBehavior: googleSuccess,
                llmBehavior: .failure(.timedOut),
                expectedVisibleState: "Google card: DIAGNOSTIC_FIXTURE_GOOGLE_TRANSLATION; LLM card: Request timed out."
            )
        case .malformedLLM:
            return .init(
                initialInput: DiagnosticsFixtures.term,
                destination: .translationPopover,
                googleBehavior: googleSuccess,
                llmBehavior: .failure(.invalidResponse),
                expectedVisibleState: "Google card: DIAGNOSTIC_FIXTURE_GOOGLE_TRANSLATION; LLM card: The service returned an invalid response."
            )
        case .credentialReload:
            return .init(
                initialInput: "",
                destination: .settings,
                googleBehavior: googleSuccess,
                llmBehavior: llmSuccess,
                expectedVisibleState: "Settings: credentials unavailable; Reload restores synthetic placeholders."
            )
        case .rollbackIncomplete:
            return .init(
                initialInput: "",
                destination: .settings,
                googleBehavior: googleSuccess,
                llmBehavior: llmSuccess,
                expectedVisibleState: "Settings save: needs attention after incomplete rollback."
            )
        }
    }
}

public enum DiagnosticsDestination: Equatable, Sendable {
    case translationPopover
    case settings
}

public enum DiagnosticsProviderBehavior: Equatable, Sendable {
    case success(primaryText: String)
    case failure(TranslationProviderError)
    case pending(primaryText: String)
}

public struct DiagnosticsScenarioConfiguration: Equatable, Sendable {
    public let initialInput: String
    public let destination: DiagnosticsDestination
    public let googleBehavior: DiagnosticsProviderBehavior
    public let llmBehavior: DiagnosticsProviderBehavior
    public let expectedVisibleState: String

    public init(
        initialInput: String,
        destination: DiagnosticsDestination,
        googleBehavior: DiagnosticsProviderBehavior,
        llmBehavior: DiagnosticsProviderBehavior,
        expectedVisibleState: String
    ) {
        self.initialInput = initialInput
        self.destination = destination
        self.googleBehavior = googleBehavior
        self.llmBehavior = llmBehavior
        self.expectedVisibleState = expectedVisibleState
    }
}

public struct DiagnosticsUsageError: Error, Equatable, Sendable {
    public let message: String

    public init() {
        let validNames = DiagnosticsScenario.allCases.map(\.rawValue).joined(separator: ", ")
        message = "usage: InstantTranslationDiagnostics <scenario>\nvalid scenarios: \(validNames)"
    }
}

enum DiagnosticsFixtures {
    static let term = "DIAGNOSTIC_FIXTURE_TERM"
    static let googleTranslation = "DIAGNOSTIC_FIXTURE_GOOGLE_TRANSLATION"
    static let llmTranslation = "DIAGNOSTIC_FIXTURE_LLM_TRANSLATION"
    static let googleCredential = "DIAGNOSTIC_FIXTURE_GOOGLE_KEY"
    static let llmCredential = "DIAGNOSTIC_FIXTURE_LLM_KEY"
    static let llmModel = "DIAGNOSTIC_FIXTURE_MODEL"
    static let prompt = "DIAGNOSTIC_FIXTURE_PROMPT"
}
