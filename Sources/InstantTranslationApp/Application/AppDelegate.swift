import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var application: ApplicationContainer?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // accessory 生命周期由 AppDelegate 持有组合根，避免无 Dock 应用启动后服务提前释放。
        configureActivationPolicy()
        Task { [weak self] in
            guard let self else { return }
            let application = await ApplicationContainer.make()
            self.application = application
            application.start()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        application?.stop()
        application = nil
    }

    public func configureActivationPolicy() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
