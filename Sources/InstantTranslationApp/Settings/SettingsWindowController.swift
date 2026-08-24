import AppKit
import SwiftUI

/// 设置窗口的固定尺寸。窗口不可缩放，这个值就是内容唯一能用的画布，
/// 视图层的密度参数（SettingsDensity）都是按它定的。
enum SettingsWindowMetrics {
    static let contentSize = NSSize(width: 520, height: 620)
}

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
            contentRect: NSRect(origin: .zero, size: SettingsWindowMetrics.contentSize),
            // 不可缩放：设置项是一份固定清单，没有需要用户自己放大的可变内容，
            // 溢出由 Form 自身滚动消化。
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Loquat Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        // autosave 名字带上尺寸版本：旧名下存着 620x700 的 frame，
        // 沿用会把窗口重新撑回改版前的大小，位置记忆就得连同尺寸一起作废。
        window.setFrameAutosaveName("InstantTranslationSettingsWindow.compact")
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
            title: "Quit Loquat",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = .command
        quit.target = NSApplication.shared
        applicationMenu.addItem(quit)

        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        mainMenu.addItem(makeEditMenuItem())
        NSApplication.shared.mainMenu = mainMenu
    }

    /// 菜单栏辅助应用没有默认的 Edit 菜单，Cmd+C/V/X/A/Z 等标准编辑快捷键
    /// 就无法通过 key equivalent 路由到设置页里的 TextField / SecureField / TextEditor，
    /// 表现为只能右键粘贴。这里补一个标准 Edit 菜单，让键盘快捷键粘贴/复制/剪切恢复工作。
    private func makeEditMenuItem() -> NSMenuItem {
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")

        let undo = NSMenuItem(
            title: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        undo.keyEquivalentModifierMask = .command
        editMenu.addItem(undo)

        let redo = NSMenuItem(
            title: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "Z"
        )
        redo.keyEquivalentModifierMask = .command
        editMenu.addItem(redo)
        editMenu.addItem(.separator())

        let cut = NSMenuItem(
            title: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        cut.keyEquivalentModifierMask = .command
        editMenu.addItem(cut)

        let copy = NSMenuItem(
            title: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        copy.keyEquivalentModifierMask = .command
        editMenu.addItem(copy)

        let paste = NSMenuItem(
            title: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        paste.keyEquivalentModifierMask = .command
        editMenu.addItem(paste)

        let selectAll = NSMenuItem(
            title: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        selectAll.keyEquivalentModifierMask = .command
        editMenu.addItem(selectAll)

        editItem.submenu = editMenu
        return editItem
    }
}
