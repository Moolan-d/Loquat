import AppKit
import OSLog

@MainActor
public final class TranslationPopoverController: NSObject, NSPopoverDelegate {
    public let popover = NSPopover()
    public let contentController: PopoverContentController

    private let focusRequester: any PopoverFocusRequesting
    private let activateApplication: @MainActor () -> Void
    private let signposter = OSSignposter(
        subsystem: "com.instanttranslation.macos",
        category: "popover"
    )

    public init(
        contentView: NSView,
        focusRequester: any PopoverFocusRequesting,
        activateApplication: @escaping @MainActor () -> Void = {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    ) {
        // controller 持有 transient popover；点击外部只关闭窗口，不取消仍在运行的翻译会话。
        contentController = PopoverContentController(contentView: contentView)
        self.focusRequester = focusRequester
        self.activateApplication = activateApplication
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
            // 只在展示路径激活：Cmd+V 等编辑快捷键靠主菜单 key equivalent 分发，
            // 而其 target 解析依赖应用处于激活态；关闭时激活会平白抢走前台应用焦点。
            activateApplication()
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
