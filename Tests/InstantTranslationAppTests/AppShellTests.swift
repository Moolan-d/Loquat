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

private final class FakeShortcutRegistrar: GlobalShortcutRegistering {
    func register(
        _ shortcut: KeyboardShortcut?,
        action: @escaping @MainActor () -> Void
    ) throws {}

    func unregister() {}
}
