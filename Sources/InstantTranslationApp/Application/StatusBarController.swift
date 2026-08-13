import AppKit
import InstantTranslationInfrastructure

@MainActor
public final class StatusBarController {
    public let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    private let popoverController: TranslationPopoverController
    private let shortcutRegistrar: GlobalShortcutRegistering

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
        guard let button = statusItem.button else { return }
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
