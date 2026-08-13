import XCTest
@testable import InstantTranslationApp

@MainActor
final class ApplicationStartupCoordinatorTests: XCTestCase {
    func testFailurePresentsSanitizedCredentialStateWithRetryAndQuitActions() async {
        let presenter = RecordingStartupFailurePresenter()
        var quitCallCount = 0
        let coordinator = ApplicationStartupCoordinator(
            makeApplication: {
                throw SensitiveStartupError(
                    description: "OSStatus -34018 TEAM123.com.instanttranslation.macos secret-value"
                )
            },
            failurePresenter: presenter,
            quit: { quitCallCount += 1 }
        )

        await coordinator.start()

        XCTAssertEqual(coordinator.state, .failed(.credentialStorageUnavailable))
        XCTAssertEqual(presenter.failures, [.credentialStorageUnavailable])
        let presentation = ApplicationStartupFailure.credentialStorageUnavailable.presentation
        XCTAssertEqual(presentation.title, "Credential Storage Unavailable")
        XCTAssertEqual(
            presentation.message,
            "Loquat could not open or migrate credentials safely. Retry, or quit the app."
        )
        XCTAssertFalse(presentation.message.contains("-34018"))
        XCTAssertFalse(presentation.message.contains("TEAM123"))
        XCTAssertFalse(presentation.message.contains("secret-value"))

        presenter.triggerQuit()
        XCTAssertEqual(quitCallCount, 1)
    }

    func testRetryAfterFailureStartsExactlyOneApplication() async throws {
        let presenter = RecordingStartupFailurePresenter()
        let application = RecordingApplicationLifecycle()
        var factoryCallCount = 0
        let coordinator = ApplicationStartupCoordinator(
            makeApplication: {
                factoryCallCount += 1
                if factoryCallCount == 1 {
                    throw SensitiveStartupError(description: "secret-value")
                }
                return application
            },
            failurePresenter: presenter,
            quit: {}
        )

        await coordinator.start()
        presenter.triggerRetry()
        try await waitUntil { coordinator.state == .running }

        XCTAssertEqual(factoryCallCount, 2)
        XCTAssertEqual(application.startCallCount, 1)
        XCTAssertNil(coordinator.failure)
    }

    func testRepeatedRetryWhileStartingDoesNotCreateDuplicateApplication() async throws {
        let presenter = RecordingStartupFailurePresenter()
        let application = RecordingApplicationLifecycle()
        let gate = StartupFactoryGate()
        var factoryCallCount = 0
        let coordinator = ApplicationStartupCoordinator(
            makeApplication: {
                factoryCallCount += 1
                if factoryCallCount == 1 {
                    throw SensitiveStartupError(description: "secret-value")
                }
                await gate.wait()
                return application
            },
            failurePresenter: presenter,
            quit: {}
        )

        await coordinator.start()
        presenter.triggerRetry()
        presenter.triggerRetry()
        try await waitUntil { coordinator.state == .starting }
        gate.open()
        try await waitUntil { coordinator.state == .running }
        presenter.triggerRetry()
        await Task.yield()

        XCTAssertEqual(factoryCallCount, 2)
        XCTAssertEqual(application.startCallCount, 1)
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("condition was not satisfied", file: file, line: line)
        throw StartupTestTimeout()
    }
}

private struct SensitiveStartupError: Error {
    let description: String
}

@MainActor
private final class RecordingStartupFailurePresenter: StartupFailurePresenting {
    private(set) var failures: [ApplicationStartupFailure] = []
    private var retry: (@MainActor @Sendable () -> Void)?
    private var quit: (@MainActor @Sendable () -> Void)?

    func present(
        _ failure: ApplicationStartupFailure,
        retry: @escaping @MainActor @Sendable () -> Void,
        quit: @escaping @MainActor @Sendable () -> Void
    ) {
        failures.append(failure)
        self.retry = retry
        self.quit = quit
    }

    func triggerRetry() {
        retry?()
    }

    func triggerQuit() {
        quit?()
    }
}

@MainActor
private final class RecordingApplicationLifecycle: ApplicationLifecycle {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    func start() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }
}

@MainActor
private final class StartupFactoryGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private struct StartupTestTimeout: Error {}
