import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var container: ApplicationContainer?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // accessory 生命周期由 AppDelegate 持有组合根，避免无 Dock 应用启动后服务提前释放。
        configureActivationPolicy()
        Task {
            do {
                let container = try await ApplicationContainer.make()
                self.container = container
                container.start()
            } catch {
                // 凭据 backend 或迁移失败必须停在组合根；日志只记录稳定边界，不展开底层错误。
                NSLog("credential initialization failed")
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        container?.stop()
    }

    public func configureActivationPolicy() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
