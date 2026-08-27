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
    private var readFailures: [CredentialKey: Int] = [:]
    private var recordedOperations: [CredentialOperation] = []
    private var recordedReadCallCount = 0

    init(values: [CredentialKey: String] = [:]) {
        self.values = values
    }

    func read(_ key: CredentialKey) throws -> String? {
        try lock.withLock {
            recordedReadCallCount += 1
            let remaining = readFailures[key] ?? 0
            if remaining > 0 {
                readFailures[key] = remaining - 1
                throw SettingsFakeError.injected
            }
            return values[key]
        }
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

    var readCallCount: Int {
        lock.withLock { recordedReadCallCount }
    }

    func failNext(
        _ operation: CredentialOperation,
        timing: FakeFailureTiming = .beforeMutation
    ) {
        lock.withLock {
            failures.append(Failure(operation: operation, timing: timing))
        }
    }

    func failNextRead(_ key: CredentialKey) {
        lock.withLock {
            readFailures[key, default: 0] += 1
        }
    }

    private func consumeFailure(for operation: CredentialOperation) -> FakeFailureTiming? {
        guard let index = failures.firstIndex(where: { $0.operation == operation }) else {
            return nil
        }
        return failures.remove(at: index).timing
    }
}

actor SuspendingPreferencesStore: PreferencesStoring {
    private var value: AppPreferences
    private var suspendLoad = false
    private var suspendSave = false
    private var saveFailure: FakeFailureTiming?
    private var loadContinuation: CheckedContinuation<Void, Never>?
    private var saveContinuation: CheckedContinuation<Void, Never>?
    private(set) var saveCallCount = 0

    init(_ value: AppPreferences = AppPreferences()) {
        self.value = value
    }

    func load() async -> AppPreferences {
        if suspendLoad {
            suspendLoad = false
            await withCheckedContinuation { continuation in
                loadContinuation = continuation
            }
        }
        return value
    }

    func save(_ preferences: AppPreferences) async throws {
        saveCallCount += 1
        let failure = saveFailure
        saveFailure = nil
        if failure == .beforeMutation {
            throw SettingsFakeError.injected
        }
        value = preferences
        if suspendSave {
            suspendSave = false
            await withCheckedContinuation { continuation in
                saveContinuation = continuation
            }
        }
        if failure == .afterMutation {
            throw SettingsFakeError.injected
        }
    }

    func suspendNextLoad() {
        suspendLoad = true
    }

    func suspendNextSave(failure: FakeFailureTiming? = nil) {
        suspendSave = true
        saveFailure = failure
    }

    func waitUntilLoadSuspends() async {
        while loadContinuation == nil {
            await Task.yield()
        }
    }

    func waitUntilSaveSuspends() async {
        while saveContinuation == nil {
            await Task.yield()
        }
    }

    func resumeLoad() {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func resumeSave() {
        saveContinuation?.resume()
        saveContinuation = nil
    }

    func stored() -> AppPreferences {
        value
    }
}

@MainActor
final class FakeLaunchAtLoginController: LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus
    private(set) var setValues: [Bool] = []
    private var failures: [FakeFailureTiming] = []

    init(isEnabled: Bool = false) {
        status = isEnabled ? .enabled : .notRegistered
    }

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func setEnabled(_ enabled: Bool) throws {
        setValues.append(enabled)
        let failure = failures.isEmpty ? nil : failures.removeFirst()
        if failure == .beforeMutation {
            throw SettingsFakeError.injected
        }
        status = enabled ? .enabled : .notRegistered
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
    var status: LaunchAtLoginStatus
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(status: LaunchAtLoginStatus = .notRegistered) {
        self.status = status
    }

    func register() {
        registerCallCount += 1
        status = .enabled
    }

    func unregister() {
        unregisterCallCount += 1
        status = .notRegistered
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
    private var llmContinuations: [CheckedContinuation<ConnectionTestState, Never>?] = []
    private(set) var googleKeys: [String] = []
    private(set) var llmConfigurations: [LLMProviderConfiguration] = []

    func testGoogle(apiKey: String) async -> ConnectionTestState {
        googleKeys.append(apiKey)
        return await withCheckedContinuation { continuation in
            googleContinuations.append(continuation)
        }
    }

    func testLLM(configuration: LLMProviderConfiguration) async -> ConnectionTestState {
        llmConfigurations.append(configuration)
        return await withCheckedContinuation { continuation in
            llmContinuations.append(continuation)
        }
    }

    func googleCallCount() -> Int {
        googleKeys.count
    }

    func completeGoogle(at index: Int, with state: ConnectionTestState) {
        googleContinuations[index]?.resume(returning: state)
        googleContinuations[index] = nil
    }

    func llmCallCount() -> Int {
        llmConfigurations.count
    }

    func completeLLM(at index: Int, with state: ConnectionTestState) {
        llmContinuations[index]?.resume(returning: state)
        llmContinuations[index] = nil
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
