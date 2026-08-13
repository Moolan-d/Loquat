import AppKit
import SwiftUI

@MainActor
public final class SettingsWindowController: NSWindowController {
    public let model: SettingsViewModel

    private let notificationCenter: NotificationCenter
    private let activateApplication: @MainActor () -> Void
    private let orderWindowFront: @MainActor (NSWindow, Any?) -> Void

    public convenience init(model: SettingsViewModel) {
        self.init(model: model, installApplicationMenu: true)
    }

    convenience init(model: SettingsViewModel, installApplicationMenu: Bool) {
        self.init(
            model: model,
            notificationCenter: .default,
            activateApplication: {
                NSApplication.shared.activate(ignoringOtherApps: true)
            },
            orderWindowFront: { window, sender in
                window.makeKeyAndOrderFront(sender)
            },
            installApplicationMenu: installApplicationMenu
        )
    }

    init(
        model: SettingsViewModel,
        notificationCenter: NotificationCenter,
        activateApplication: @escaping @MainActor () -> Void,
        orderWindowFront: @escaping @MainActor (NSWindow, Any?) -> Void,
        installApplicationMenu: Bool
    ) {
        self.model = model
        self.notificationCenter = notificationCenter
        self.activateApplication = activateApplication
        self.orderWindowFront = orderWindowFront

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Instant Translation Settings"
        // 控制器由组合根强持有，窗口关闭只隐藏；再次打开复用同一模型与窗口。
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.setFrameAutosaveName("InstantTranslationSettingsWindow")
        super.init(window: window)

        notificationCenter.addObserver(
            self,
            selector: #selector(openSettingsNotification(_:)),
            name: .openInstantTranslationSettings,
            object: nil
        )

        if installApplicationMenu {
            installMainMenu()
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc public func showSettings(_ sender: Any?) {
        showWindow(sender)
        activateApplication()
        if let window {
            orderWindowFront(window, sender)
        }
    }

    @objc private func openSettingsNotification(_ notification: Notification) {
        showSettings(nil)
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings(_:)),
            keyEquivalent: ","
        )
        settings.keyEquivalentModifierMask = .command
        settings.target = self
        applicationMenu.addItem(settings)
        applicationMenu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Instant Translation",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = .command
        quit.target = NSApplication.shared
        applicationMenu.addItem(quit)

        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        NSApplication.shared.mainMenu = mainMenu
    }
}
