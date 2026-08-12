import Foundation
import InstantTranslationCore
import InstantTranslationInfrastructure
@testable import InstantTranslationApp

enum SettingsFakeError: Error {
    case injected
}

enum FakeFailureTiming: Sendable {
    case beforeMutation
    case afterMutation
}

actor MemoryPreferencesStore: PreferencesStoring {
    private var value: AppPreferences
    private var nextFailure: FakeFailureTiming?
    private(set) var saveCallCount = 0

    init(_ value: AppPreferences = AppPreferences()) {
        self.value = value
    }

    func load() -> AppPreferences {
        value
    }

    func save(_ preferences: AppPreferences) throws {
        saveCallCount += 1
        let failure = nextFailure
        nextFailure = nil
        if failure == .beforeMutation {
            throw SettingsFakeError.injected
        }
        value = preferences
        if failure == .afterMutation {
            throw SettingsFakeError.injected
        }
    }

    func failNextSave(_ timing: FakeFailureTiming) {
        nextFailure = timing
    }
}

enum CredentialOperation: Equatable, Sendable {
    case write(CredentialKey)
    case delete(CredentialKey)
}

final class MemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    private struct Failure {
        let operation: CredentialOperation
        let timing: FakeFailureTiming
    }

    private let lock = NSLock()
    private var values: [CredentialKey: String]
    private var failures: [Failure] = []
    private var recordedOperations: [CredentialOperation] = []

    init(values: [CredentialKey: String] = [:]) {
        self.values = values
    }

    func read(_ key: CredentialKey) throws -> String? {
        lock.withLock { values[key] }
    }

    func write(_ value: String, for key: CredentialKey) throws {
        try lock.withLock {
            let operation = CredentialOperation.write(key)
            recordedOperations.append(operation)
            let failure = consumeFailure(for: operation)
            if failure == .beforeMutation {
                throw SettingsFakeError.injected
            }
            values[key] = value
            if failure == .afterMutation {
                throw SettingsFakeError.injected
            }
        }
    }

    func delete(_ key: CredentialKey) throws {
        try lock.withLock {
            let operation = CredentialOperation.delete(key)
            recordedOperations.append(operation)
            let failure = consumeFailure(for: operation)
            if failure == .beforeMutation {
                throw SettingsFakeError.injected
            }
            values[key] = nil
            if failure == .afterMutation {
                throw SettingsFakeError.injected
            }
        }
    }

    func stored(_ key: CredentialKey) -> String? {
        lock.withLock { values[key] }
    }

    var operations: [CredentialOperation] {
        lock.withLock { recordedOperations }
    }

    func failNext(
        _ operation: CredentialOperation,
        timing: FakeFailureTiming = .beforeMutation
    ) {
        lock.withLock {
            failures.append(Failure(operation: operation, timing: timing))
        }
    }

    private func consumeFailure(for operation: CredentialOperation) -> FakeFailureTiming? {
        guard let index = failures.firstIndex(where: { $0.operation == operation }) else {
            return nil
        }
        return failures.remove(at: index).timing
    }
}

@MainActor
final class FakeLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool
    private(set) var setValues: [Bool] = []
    private var failures: [FakeFailureTiming] = []

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        setValues.append(enabled)
        let failure = failures.isEmpty ? nil : failures.removeFirst()
        if failure == .beforeMutation {
            throw SettingsFakeError.injected
        }
        isEnabled = enabled
        if failure == .afterMutation {
            throw SettingsFakeError.injected
        }
    }

    func failNextSet(_ timing: FakeFailureTiming) {
        failures.append(timing)
    }
}

@MainActor
final class FakeLaunchAtLoginService: LaunchAtLoginServicing {
    var isEnabled = false
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    func register() {
        registerCallCount += 1
        isEnabled = true
    }

    func unregister() {
        unregisterCallCount += 1
        isEnabled = false
    }
}

@MainActor
final class FakeSettingsShortcutRegistrar: GlobalShortcutRegistering {
    private(set) var registeredShortcut: KeyboardShortcut?
    private(set) var registerValues: [KeyboardShortcut?] = []
    private(set) var unregisterCallCount = 0
    private var failures: [FakeFailureTiming] = []

    init(registeredShortcut: KeyboardShortcut? = nil) {
        self.registeredShortcut = registeredShortcut
    }

    func register(
        _ shortcut: KeyboardShortcut?,
        action: @escaping @MainActor () -> Void
    ) throws {
        registerValues.append(shortcut)
        registeredShortcut = nil
        let failure = failures.isEmpty ? nil : failures.removeFirst()
        if failure == .beforeMutation {
            throw SettingsFakeError.injected
        }
        registeredShortcut = shortcut
        if failure == .afterMutation {
            throw SettingsFakeError.injected
        }
    }

    func unregister() {
        unregisterCallCount += 1
        registeredShortcut = nil
    }

    func failNextRegister(_ timing: FakeFailureTiming) {
        failures.append(timing)
    }
}

actor RecordingConnectionTester: ProviderConnectionTesting {
    private(set) var googleKeys: [String] = []
    private(set) var llmConfigurations: [LLMProviderConfiguration] = []
    var googleResult: ConnectionTestState
    var llmResult: ConnectionTestState

    init(
        googleResult: ConnectionTestState = .success,
        llmResult: ConnectionTestState = .success
    ) {
        self.googleResult = googleResult
        self.llmResult = llmResult
    }

    func testGoogle(apiKey: String) -> ConnectionTestState {
        googleKeys.append(apiKey)
        return googleResult
    }

    func testLLM(configuration: LLMProviderConfiguration) -> ConnectionTestState {
        llmConfigurations.append(configuration)
        return llmResult
    }
}

actor ControlledConnectionTester: ProviderConnectionTesting {
    private var googleContinuations: [CheckedContinuation<ConnectionTestState, Never>?] = []
    private(set) var googleKeys: [String] = []

    func testGoogle(apiKey: String) async -> ConnectionTestState {
        googleKeys.append(apiKey)
        return await withCheckedContinuation { continuation in
            googleContinuations.append(continuation)
        }
    }

    func testLLM(configuration: LLMProviderConfiguration) -> ConnectionTestState {
        .success
    }

    func googleCallCount() -> Int {
        googleKeys.count
    }

    func completeGoogle(at index: Int, with state: ConnectionTestState) {
        googleContinuations[index]?.resume(returning: state)
        googleContinuations[index] = nil
    }
}

actor RecordingHTTPTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    private var responses: [HTTPResponse]

    init(responses: [HTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return responses.removeFirst()
    }
}
