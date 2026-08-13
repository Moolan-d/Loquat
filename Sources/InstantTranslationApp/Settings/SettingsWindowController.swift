import AppKit
import SwiftUI

@MainActor
public final class SettingsWindowController: NSWindowController {
    public let model: SettingsViewModel

    private let notificationCenter: NotificationCenter
    private let activateApplication: @MainActor () -> Void
    private let orderWindowFront: @MainActor (NSWindow, Any?) -> Void
    private let makeWindow: @MainActor (SettingsViewModel) -> NSWindow
    private var retainedSettingsWindow: NSWindow?
    private var isConstructingSettingsWindow = false
    private var isSettingsPresentationPending = false

    var isSettingsWindowConstructed: Bool { retainedSettingsWindow != nil }

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
            installApplicationMenu: installApplicationMenu,
            makeWindow: Self.makeProductionWindow(model:)
        )
    }

    init(
        model: SettingsViewModel,
        notificationCenter: NotificationCenter,
        activateApplication: @escaping @MainActor () -> Void,
        orderWindowFront: @escaping @MainActor (NSWindow, Any?) -> Void,
        installApplicationMenu: Bool,
        makeWindow: @escaping @MainActor (SettingsViewModel) -> NSWindow = SettingsWindowController.makeProductionWindow(model:)
    ) {
        self.model = model
        self.notificationCenter = notificationCenter
        self.activateApplication = activateApplication
        self.orderWindowFront = orderWindowFront
        self.makeWindow = makeWindow
        super.init(window: nil)

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
        if isConstructingSettingsWindow {
            // 构造期间的同步重入只登记一次展示；窗口发布后由外层调用统一完成。
            isSettingsPresentationPending = true
            return
        }
        if let retainedSettingsWindow {
            presentSettingsWindow(retainedSettingsWindow, sender: sender)
            return
        }

        isConstructingSettingsWindow = true
        isSettingsPresentationPending = true
        let created = makeWindow(model)
        retainedSettingsWindow = created
        window = created
        isConstructingSettingsWindow = false

        guard isSettingsPresentationPending else { return }
        isSettingsPresentationPending = false
        presentSettingsWindow(created, sender: sender)
    }

    private func presentSettingsWindow(_ window: NSWindow, sender: Any?) {
        activateApplication()
        orderWindowFront(window, sender)
    }

    @objc private func openSettingsNotification(_ notification: Notification) {
        showSettings(nil)
    }

    static func makeProductionWindow(model: SettingsViewModel) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Instant Translation Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.setFrameAutosaveName("InstantTranslationSettingsWindow")
        return window
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
