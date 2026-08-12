import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var container: ApplicationContainer?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // accessory 生命周期由 AppDelegate 持有组合根，避免无 Dock 应用启动后服务提前释放。
        configureActivationPolicy()
        Task {
            let container = await ApplicationContainer.make()
            self.container = container
            container.start()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        container?.stop()
    }

    public func configureActivationPolicy() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
