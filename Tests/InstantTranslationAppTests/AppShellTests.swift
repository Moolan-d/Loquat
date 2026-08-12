import AppKit
import XCTest
import InstantTranslationInfrastructure
@testable import InstantTranslationApp

@MainActor
final class AppShellTests: XCTestCase {
    func testPopoverIsTransientAndUsesNativeMaterial() {
        let controller = TranslationPopoverController(contentView: NSView())

        XCTAssertEqual(controller.popover.behavior, .transient)
        XCTAssertEqual(controller.contentController.materialView.material, .popover)
    }

    func testStatusBarUsesTemplateSymbolAndHasNoDockActivationPolicy() {
        AppDelegate().configureActivationPolicy()
        let controller = StatusBarController(
            popoverController: TranslationPopoverController(contentView: NSView()),
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
}

private final class FakeShortcutRegistrar: GlobalShortcutRegistering {
    func register(
        _ shortcut: KeyboardShortcut?,
        action: @escaping @MainActor () -> Void
    ) throws {}

    func unregister() {}
}
