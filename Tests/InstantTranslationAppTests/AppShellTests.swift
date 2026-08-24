import AppKit
import XCTest
import InstantTranslationInfrastructure
@testable import InstantTranslationApp

@MainActor
final class AppShellTests: XCTestCase {
    func testPopoverIsTransientAndUsesNativeMaterial() {
        let controller = TranslationPopoverController(
            contentView: NSView(),
            focusRequester: TranslationInputFocusController()
        )

        XCTAssertEqual(controller.popover.behavior, .transient)
        XCTAssertEqual(controller.contentController.materialView.material, .popover)
    }

    func testReducedTransparencyBackgroundRefreshesAcrossEffectiveAppearanceChanges() throws {
        let controller = PopoverContentController(
            contentView: NSView(),
            shouldReduceTransparency: { true }
        )

        controller.view.appearance = NSAppearance(named: .aqua)
        controller.materialView.viewDidChangeEffectiveAppearance()
        let light = try resolvedBackgroundColor(controller.materialView)

        controller.view.appearance = NSAppearance(named: .darkAqua)
        controller.materialView.viewDidChangeEffectiveAppearance()
        let dark = try resolvedBackgroundColor(controller.materialView)

        XCTAssertEqual(controller.materialView.material, .windowBackground)
        XCTAssertEqual(controller.materialView.blendingMode, .withinWindow)
        XCTAssertNotEqual(light.redComponent, dark.redComponent)
    }

    func testNormalTransparencyRemainsNativePopoverAndClearAcrossAppearanceChanges() throws {
        let controller = PopoverContentController(
            contentView: NSView(),
            shouldReduceTransparency: { false }
        )

        controller.view.appearance = NSAppearance(named: .aqua)
        controller.materialView.viewDidChangeEffectiveAppearance()
        let light = try resolvedBackgroundColor(controller.materialView)

        controller.view.appearance = NSAppearance(named: .darkAqua)
        controller.materialView.viewDidChangeEffectiveAppearance()
        let dark = try resolvedBackgroundColor(controller.materialView)

        XCTAssertEqual(controller.materialView.material, .popover)
        XCTAssertEqual(controller.materialView.blendingMode, .behindWindow)
        XCTAssertEqual(light.alphaComponent, 0)
        XCTAssertEqual(dark.alphaComponent, 0)
    }

    func testPopoverDidShowFocusesDesignatedInputEveryTime() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 370, height: 430))
        let input = NSTextField(frame: NSRect(x: 10, y: 20, width: 200, height: 24))
        let other = NSTextField(frame: NSRect(x: 10, y: 60, width: 200, height: 24))
        contentView.addSubview(input)
        contentView.addSubview(other)

        let focusController = TranslationInputFocusController()
        focusController.bind(input)
        let controller = TranslationPopoverController(
            contentView: contentView,
            focusRequester: focusController
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 370, height: 430),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        window.contentView = controller.contentController.view

        XCTAssertTrue(window.makeFirstResponder(other))
        controller.popoverDidShow(
            Notification(name: NSPopover.didShowNotification, object: controller.popover)
        )
        assertFirstResponder(input, in: window)

        XCTAssertTrue(window.makeFirstResponder(other))
        controller.popoverDidShow(
            Notification(name: NSPopover.didShowNotification, object: controller.popover)
        )
        assertFirstResponder(input, in: window)
    }

    func testPopoverHeightFollowsContentAndClampsToConfiguredBounds() {
        // 断言生产配置本身，而不是就地重建一份同样的数字。
        let metrics = PopoverContentMetrics.standard

        XCTAssertEqual(metrics.size(forFittingHeight: 120).height, 200, accuracy: 0.01)
        XCTAssertEqual(metrics.size(forFittingHeight: 300).height, 300, accuracy: 0.01)
        // 结果卡片堆叠得再高，弹窗也不会长到超出屏幕；余量交给结果区自身滚动。
        XCTAssertEqual(metrics.size(forFittingHeight: 5_000).height, 560, accuracy: 0.01)
        XCTAssertEqual(
            metrics.size(forFittingHeight: 300).width,
            TranslationView.contentWidth,
            accuracy: 0.01
        )
    }

    func testShowingPopoverActivatesApplicationAndClosingDoesNot() {
        // Cmd+V 走主菜单 key equivalent，其 validation 由 NSApp.targetForAction: 解析；
        // accessory 应用未激活时该解析返回 nil，粘贴被静默丢弃（打字仍正常，因为按键
        // 直接进 field editor）。设置窗口早已在展示前 activate，弹窗必须保持同一约定。
        var activationCount = 0
        let controller = TranslationPopoverController(
            contentView: NSView(frame: NSRect(x: 0, y: 0, width: 370, height: 430)),
            focusRequester: TranslationInputFocusController(),
            activateApplication: { activationCount += 1 }
        )
        let button = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength).button!

        controller.toggle(relativeTo: button)
        XCTAssertEqual(activationCount, 1, "showing the popover must activate the app")

        controller.close()
        XCTAssertEqual(activationCount, 1, "closing the popover must not activate the app")
    }

    func testGlobalShortcutIsSuspendedWhileSettingsIsOpen() {
        // 展示路径必定 activate、关闭路径必定不 activate（见上一个用例），
        // 因此激活次数就是"弹窗被唤起了几次"的可靠观测点；
        // headless 下 NSPopover.isShown 不可靠，不拿它做断言。
        var activations = 0
        var clipboardPreparations = 0
        let settingsIsOpen = MutableFlag(true)
        let popover = TranslationPopoverController(
            contentView: NSView(frame: NSRect(x: 0, y: 0, width: 370, height: 430)),
            focusRequester: TranslationInputFocusController(),
            activateApplication: { activations += 1 }
        )
        let controller = StatusBarController(
            popoverController: popover,
            shortcutRegistrar: FakeShortcutRegistrar()
        )
        controller.isShortcutSuspended = { settingsIsOpen.value }
        controller.onShortcutOpen = { clipboardPreparations += 1 }
        defer { popover.close() }

        // 面板开着：快捷键整条路径都不走——不唤起弹窗，也不顺手去读剪贴板。
        controller.toggleFromShortcut()
        XCTAssertEqual(activations, 0)
        XCTAssertEqual(clipboardPreparations, 0)

        settingsIsOpen.value = false
        controller.toggleFromShortcut()
        XCTAssertEqual(activations, 1)
        XCTAssertEqual(clipboardPreparations, 1)
    }

    func testStatusBarClickStillTogglesWhileSettingsIsOpen() {
        // 只拦快捷键。点菜单栏图标是用户明确指向弹窗的操作，没有误触之虞。
        var activations = 0
        let popover = TranslationPopoverController(
            contentView: NSView(frame: NSRect(x: 0, y: 0, width: 370, height: 430)),
            focusRequester: TranslationInputFocusController(),
            activateApplication: { activations += 1 }
        )
        let controller = StatusBarController(
            popoverController: popover,
            shortcutRegistrar: FakeShortcutRegistrar()
        )
        controller.isShortcutSuspended = { true }
        defer { popover.close() }

        controller.statusItem.button?.performClick(nil)

        XCTAssertEqual(activations, 1)
    }

    func testStatusBarUsesTemplateSymbolAndHasNoDockActivationPolicy() {
        AppDelegate().configureActivationPolicy()
        let controller = StatusBarController(
            popoverController: TranslationPopoverController(
                contentView: NSView(),
                focusRequester: TranslationInputFocusController()
            ),
            shortcutRegistrar: FakeShortcutRegistrar()
        )

        XCTAssertTrue(controller.statusItem.button?.image?.isTemplate ?? false)
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
    }

    func testClipboardSourceIgnoresNonTextPasteboardContent() async throws {
        let source = ClipboardInputSource(readString: { nil })

        let text = try await source.read()
        XCTAssertNil(text)
    }

    func testFiveHundredPopoverControllerConstructionsReleaseContent() async {
        var references: [WeakBox<PopoverContentController>] = []

        for _ in 0..<500 {
            autoreleasepool {
                let controller = TranslationPopoverController(
                    contentView: NSView(),
                    focusRequester: TranslationInputFocusController()
                )
                references.append(WeakBox(controller.contentController))
            }
        }

        // preferredContentSize 的通知由 AppKit 合并到下一轮主 RunLoop；出队后再判断长期保留。
        await withCheckedContinuation { continuation in
            RunLoop.main.perform {
                continuation.resume()
            }
        }

        XCTAssertTrue(
            references.allSatisfy { $0.value == nil },
            "Popover controller lifecycle must not retain released content controllers"
        )
    }

    private func assertFirstResponder(
        _ input: NSTextField,
        in window: NSWindow,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            window.firstResponder === input || window.firstResponder === input.currentEditor(),
            "expected the designated input to be first responder",
            file: file,
            line: line
        )
    }

    private func resolvedBackgroundColor(
        _ materialView: NSVisualEffectView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> NSColor {
        let color = try XCTUnwrap(
            materialView.layer?.backgroundColor.flatMap(NSColor.init(cgColor:)),
            file: file,
            line: line
        )
        return try XCTUnwrap(
            color.usingColorSpace(.deviceRGB),
            file: file,
            line: line
        )
    }
}

private final class WeakBox<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value) {
        self.value = value
    }
}

private final class FakeShortcutRegistrar: GlobalShortcutRegistering {
    private(set) var registeredShortcut: KeyboardShortcut?

    func register(
        _ shortcut: KeyboardShortcut?,
        action: @escaping @MainActor () -> Void
    ) throws {
        registeredShortcut = shortcut
    }

    func unregister() {
        registeredShortcut = nil
    }
}

/// 让闭包读到测试中途改动的值；直接捕获 var 在 Swift 6 下是 sendable 逃逸警告。
@MainActor
private final class MutableFlag {
    var value: Bool

    init(_ value: Bool) {
        self.value = value
    }
}
