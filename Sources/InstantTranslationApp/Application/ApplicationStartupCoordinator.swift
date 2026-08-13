import AppKit

public enum ApplicationStartupFailure: Equatable, Sendable {
    case credentialStorageUnavailable

    public var presentation: ApplicationStartupFailurePresentation {
        switch self {
        case .credentialStorageUnavailable:
            ApplicationStartupFailurePresentation(
                title: "Credential Storage Unavailable",
                message: "Loquat could not open or migrate credentials safely. Retry, or quit the app."
            )
        }
    }
}

public struct ApplicationStartupFailurePresentation: Equatable, Sendable {
    public let title: String
    public let message: String
}

enum ApplicationStartupState: Equatable {
    case idle
    case starting
    case failed(ApplicationStartupFailure)
    case running
}

@MainActor
protocol ApplicationLifecycle: AnyObject {
    func start()
    func stop()
}

extension ApplicationContainer: ApplicationLifecycle {}

@MainActor
protocol StartupFailurePresenting: AnyObject {
    func present(
        _ failure: ApplicationStartupFailure,
        retry: @escaping @MainActor () -> Void,
        quit: @escaping @MainActor () -> Void
    )
}

@MainActor
final class AppKitStartupFailurePresenter: StartupFailurePresenting {
    func present(
        _ failure: ApplicationStartupFailure,
        retry: @escaping @MainActor () -> Void,
        quit: @escaping @MainActor () -> Void
    ) {
        let presentation = failure.presentation
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = presentation.title
        alert.informativeText = presentation.message
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Quit")

        // accessory 应用没有 Dock 窗口；启动失败时主动显示原生对话框，避免留下不可交互空壳。
        NSApplication.shared.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            retry()
        } else {
            quit()
        }
    }
}

@MainActor
final class ApplicationStartupCoordinator {
    private(set) var state: ApplicationStartupState = .idle

    var failure: ApplicationStartupFailure? {
        guard case .failed(let failure) = state else { return nil }
        return failure
    }

    private let makeApplication: @MainActor () async throws -> any ApplicationLifecycle
    private let failurePresenter: any StartupFailurePresenting
    private let quit: @MainActor () -> Void
    private var application: (any ApplicationLifecycle)?

    init(
        makeApplication: @escaping @MainActor () async throws -> any ApplicationLifecycle,
        failurePresenter: any StartupFailurePresenting,
        quit: @escaping @MainActor () -> Void
    ) {
        self.makeApplication = makeApplication
        self.failurePresenter = failurePresenter
        self.quit = quit
    }

    func start() async {
        guard canStart else { return }
        state = .starting

        do {
            let application = try await makeApplication()
            self.application = application
            application.start()
            state = .running
        } catch {
            // 外部只接收固定类别；禁止传播 OSStatus、路径、access group 或底层完整错误。
            let failure = ApplicationStartupFailure.credentialStorageUnavailable
            state = .failed(failure)
            failurePresenter.present(
                failure,
                retry: { [weak self] in
                    Task { @MainActor [weak self] in
                        await self?.start()
                    }
                },
                quit: quit
            )
        }
    }

    func stop() {
        application?.stop()
        application = nil
    }

    private var canStart: Bool {
        switch state {
        case .idle, .failed:
            true
        case .starting, .running:
            false
        }
    }
}
