import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var startupCoordinator = ApplicationStartupCoordinator(
        makeApplication: { try await ApplicationContainer.make() },
        failurePresenter: AppKitStartupFailurePresenter(),
        quit: { NSApplication.shared.terminate(nil) }
    )

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // accessory 生命周期由 AppDelegate 持有组合根，避免无 Dock 应用启动后服务提前释放。
        configureActivationPolicy()
        Task {
            await startupCoordinator.start()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        startupCoordinator.stop()
    }

    public func configureActivationPolicy() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
