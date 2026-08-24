import AppKit
import InstantTranslationInfrastructure

@MainActor
public final class StatusBarController {
    public let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    private let popoverController: TranslationPopoverController
    private let shortcutRegistrar: GlobalShortcutRegistering

    /// 快捷键唤起且弹窗尚未显示时调用（鼠标唤起不调、关闭动作不调）。
    public var onShortcutOpen: (@MainActor () -> Void)?

    /// 快捷键是否暂时失效。设置面板开着的时候为真：全局热键不认前台是谁，
    /// 用户正在录制的那一组键会同时打到这里，弹窗就盖到设置窗口上了。
    /// 只拦快捷键——点菜单栏图标是明确指向弹窗的操作，照常放行。
    public var isShortcutSuspended: @MainActor () -> Bool = { false }

    public init(
        popoverController: TranslationPopoverController,
        shortcutRegistrar: GlobalShortcutRegistering
    ) {
        self.popoverController = popoverController
        self.shortcutRegistrar = shortcutRegistrar

        let image = NSImage(
            systemSymbolName: "character.bubble.fill",
            accessibilityDescription: "Loquat"
        )
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    public func toggleFromShortcut() {
        guard !isShortcutSuspended() else { return }
        guard let button = statusItem.button else { return }
        if !popoverController.popover.isShown {
            onShortcutOpen?()
        }
        popoverController.toggle(relativeTo: button)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let settings = menu.addItem(
                withTitle: "Settings…",
                action: #selector(openSettings),
                keyEquivalent: ","
            )
            settings.target = self
            menu.addItem(.separator())
            let quit = menu.addItem(
                withTitle: "Quit Loquat",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
            quit.target = NSApp
            statusItem.menu = menu
            button.performClick(nil)
            statusItem.menu = nil
        } else {
            popoverController.toggle(relativeTo: button)
        }
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: .openInstantTranslationSettings, object: nil)
    }
}

public extension Notification.Name {
    static let openInstantTranslationSettings = Notification.Name(
        "openInstantTranslationSettings"
    )
}
