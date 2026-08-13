import AppKit
import OSLog

@MainActor
public final class TranslationPopoverController: NSObject, NSPopoverDelegate {
    public let popover = NSPopover()
    public let contentController: PopoverContentController

    private let focusRequester: any PopoverFocusRequesting
    private let signposter = OSSignposter(
        subsystem: "com.instanttranslation.macos",
        category: "popover"
    )

    public init(
        contentView: NSView,
        focusRequester: any PopoverFocusRequesting
    ) {
        // controller 持有 transient popover；点击外部只关闭窗口，不取消仍在运行的翻译会话。
        contentController = PopoverContentController(contentView: contentView)
        self.focusRequester = focusRequester
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = contentController
        popover.delegate = self
    }

    public func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            let interval = signposter.beginInterval("PopoverOpen")
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
            signposter.endInterval("PopoverOpen", interval)
        }
    }

    public func close() {
        popover.performClose(nil)
    }

    public func popoverDidShow(_ notification: Notification) {
        focusRequester.requestFocus()
    }
}
