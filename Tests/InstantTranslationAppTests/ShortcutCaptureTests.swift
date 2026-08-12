import AppKit
import Carbon.HIToolbox
import XCTest
import InstantTranslationInfrastructure
@testable import InstantTranslationApp

@MainActor
final class ShortcutCaptureTests: XCTestCase {
    func testPolicyAcceptsModifiedOrdinaryKey() {
        let decision = ShortcutCapturePolicy.decision(
            keyCode: 0,
            carbonModifiers: UInt32(cmdKey)
        )

        XCTAssertEqual(
            decision,
            .accept(KeyboardShortcut(keyCode: 0, carbonModifiers: UInt32(cmdKey)))
        )
    }

    func testPolicyIgnoresModifierOnlyKeys() {
        let modifierKeyCodes: [UInt16] = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

        for keyCode in modifierKeyCodes {
            XCTAssertEqual(
                ShortcutCapturePolicy.decision(
                    keyCode: keyCode,
                    carbonModifiers: UInt32(cmdKey)
                ),
                .ignore,
                "key code \(keyCode)"
            )
        }
    }

    func testPolicyRejectsBareOrdinaryKeys() {
        XCTAssertEqual(
            ShortcutCapturePolicy.decision(keyCode: 0, carbonModifiers: 0),
            .reject
        )
        XCTAssertEqual(
            ShortcutCapturePolicy.decision(keyCode: 49, carbonModifiers: 0),
            .reject
        )
    }

    func testPolicyCancelsEscapeBeforeConsideringModifiers() {
        XCTAssertEqual(
            ShortcutCapturePolicy.decision(
                keyCode: 53,
                carbonModifiers: UInt32(cmdKey)
            ),
            .cancel
        )
    }

    func testPolicyClearsForBackwardAndForwardDelete() {
        XCTAssertEqual(
            ShortcutCapturePolicy.decision(keyCode: 51, carbonModifiers: 0),
            .clear
        )
        XCTAssertEqual(
            ShortcutCapturePolicy.decision(keyCode: 117, carbonModifiers: 0),
            .clear
        )
    }

    func testSessionIgnoresDecisionsUntilRecordingBegins() {
        var session = ShortcutCaptureSession()

        let effect = session.handle(
            .accept(KeyboardShortcut(keyCode: 0, carbonModifiers: UInt32(cmdKey)))
        )

        XCTAssertEqual(effect, .none)
        XCTAssertFalse(session.isRecording)
    }

    func testRejectedAndModifierOnlyDecisionsKeepSessionRecording() {
        var session = ShortcutCaptureSession()
        session.begin()

        XCTAssertEqual(session.handle(.reject), .none)
        XCTAssertTrue(session.isRecording)
        XCTAssertEqual(session.handle(.ignore), .none)
        XCTAssertTrue(session.isRecording)
    }

    func testEscapeCancelsWithoutCommittingAChange() {
        var session = ShortcutCaptureSession()
        session.begin()

        XCTAssertEqual(session.handle(.cancel), .none)
        XCTAssertFalse(session.isRecording)
    }

    func testClearCommitsNilOnlyOnce() {
        var session = ShortcutCaptureSession()
        session.begin()

        XCTAssertEqual(session.handle(.clear), .commit(nil))
        XCTAssertFalse(session.isRecording)
        XCTAssertEqual(session.handle(.clear), .none)
    }

    func testAcceptedShortcutCommitsOnlyOnce() {
        let shortcut = KeyboardShortcut(keyCode: 0, carbonModifiers: UInt32(cmdKey))
        var session = ShortcutCaptureSession()
        session.begin()

        XCTAssertEqual(session.handle(.accept(shortcut)), .commit(shortcut))
        XCTAssertFalse(session.isRecording)
        XCTAssertEqual(session.handle(.accept(shortcut)), .none)
    }

    func testLabelShowsUnsetAndStableModifierOrder() {
        XCTAssertEqual(ShortcutCapturePolicy.label(for: nil), "Not Set")
        XCTAssertEqual(
            ShortcutCapturePolicy.label(
                for: KeyboardShortcut(
                    keyCode: 0,
                    carbonModifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)
                )
            ),
            "⌃⌥⇧⌘A"
        )
    }

    func testLabelCoversCommonPrintableNavigationAndFunctionKeys() {
        let cases: [(UInt32, UInt32, String)] = [
            (49, UInt32(cmdKey), "⌘Space"),
            (36, UInt32(optionKey), "⌥↩"),
            (48, UInt32(controlKey), "⌃⇥"),
            (123, UInt32(shiftKey), "⇧←"),
            (111, UInt32(cmdKey), "⌘F12"),
            (43, UInt32(cmdKey), "⌘,"),
            (200, UInt32(cmdKey), "⌘Key 200"),
        ]

        for (keyCode, modifiers, expected) in cases {
            XCTAssertEqual(
                ShortcutCapturePolicy.label(
                    for: KeyboardShortcut(
                        keyCode: keyCode,
                        carbonModifiers: modifiers
                    )
                ),
                expected,
                "key code \(keyCode)"
            )
        }
    }

    func testRecorderBeginsOnlyAfterClickHandlingWhileFocused() {
        let recorder = ShortcutRecorderView(onChange: { _ in })
        let window = testWindow(containing: recorder)

        XCTAssertFalse(recorder.beginRecordingFromClick())
        XCTAssertFalse(recorder.isRecording)
        XCTAssertTrue(window.makeFirstResponder(recorder))
        XCTAssertFalse(recorder.isRecording)

        XCTAssertTrue(recorder.beginRecordingFromClick())
        XCTAssertTrue(recorder.isRecording)
    }

    func testRecorderRejectsBareKeyAndCommitsAcceptedShortcutOnlyOnce() {
        var changes: [KeyboardShortcut?] = []
        let recorder = ShortcutRecorderView { changes.append($0) }
        let window = testWindow(containing: recorder)
        XCTAssertTrue(window.makeFirstResponder(recorder))
        XCTAssertTrue(recorder.beginRecordingFromClick())

        recorder.handleKey(keyCode: 0, carbonModifiers: 0)
        XCTAssertTrue(recorder.isRecording)
        XCTAssertTrue(changes.isEmpty)

        recorder.handleKey(keyCode: 0, carbonModifiers: UInt32(cmdKey))
        recorder.handleKey(keyCode: 0, carbonModifiers: UInt32(cmdKey))

        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(
            changes.first!,
            KeyboardShortcut(keyCode: 0, carbonModifiers: UInt32(cmdKey))
        )
    }

    func testRecorderEscapeCancelsAndPreservesOriginalValue() {
        let original = KeyboardShortcut(keyCode: 1, carbonModifiers: UInt32(optionKey))
        var changes: [KeyboardShortcut?] = []
        let recorder = ShortcutRecorderView(shortcut: original) { changes.append($0) }
        let window = testWindow(containing: recorder)
        XCTAssertTrue(window.makeFirstResponder(recorder))
        XCTAssertTrue(recorder.beginRecordingFromClick())

        recorder.handleKey(keyCode: 53, carbonModifiers: 0)

        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.shortcut, original)
        XCTAssertTrue(changes.isEmpty)
    }

    func testRecorderDeleteClearsAndEndsRecording() {
        let original = KeyboardShortcut(keyCode: 1, carbonModifiers: UInt32(optionKey))
        var changes: [KeyboardShortcut?] = []
        let recorder = ShortcutRecorderView(shortcut: original) { changes.append($0) }
        let window = testWindow(containing: recorder)
        XCTAssertTrue(window.makeFirstResponder(recorder))
        XCTAssertTrue(recorder.beginRecordingFromClick())

        recorder.handleKey(keyCode: 117, carbonModifiers: 0)

        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.shortcut)
        XCTAssertEqual(changes.count, 1)
        XCTAssertNil(changes.first!)
    }

    func testRecorderCancelsWhenItLosesFocusOrItsWindowResignsKey() {
        let recorder = ShortcutRecorderView(onChange: { _ in })
        let other = NSView(frame: .zero)
        let window = testWindow(containing: recorder)
        window.contentView?.addSubview(other)
        XCTAssertTrue(window.makeFirstResponder(recorder))
        XCTAssertTrue(recorder.beginRecordingFromClick())

        XCTAssertTrue(window.makeFirstResponder(other))
        XCTAssertFalse(recorder.isRecording)

        XCTAssertTrue(window.makeFirstResponder(recorder))
        XCTAssertTrue(recorder.beginRecordingFromClick())
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        XCTAssertFalse(recorder.isRecording)
    }

    func testRecorderAccessibilityReflectsUnsetRecordingAndCurrentShortcut() {
        let recorder = ShortcutRecorderView(onChange: { _ in })
        let window = testWindow(containing: recorder)

        XCTAssertEqual(recorder.accessibilityRole(), .button)
        XCTAssertEqual(recorder.accessibilityLabel(), "Keyboard shortcut")
        XCTAssertEqual(recorder.accessibilityValue() as? String, "Not Set")
        XCTAssertEqual(recorder.accessibilityHelp(), "Click to record a keyboard shortcut.")

        XCTAssertTrue(window.makeFirstResponder(recorder))
        XCTAssertTrue(recorder.beginRecordingFromClick())
        XCTAssertEqual(recorder.accessibilityValue() as? String, "Press shortcut")
        XCTAssertEqual(
            recorder.accessibilityHelp(),
            "Press a shortcut with Command, Option, Control, or Shift. Escape cancels; Delete clears."
        )

        recorder.handleKey(keyCode: 49, carbonModifiers: UInt32(cmdKey))
        XCTAssertEqual(recorder.accessibilityValue() as? String, "⌘Space")
        XCTAssertEqual(recorder.accessibilityHelp(), "Click to record a keyboard shortcut.")
    }

    func testRecorderRefreshesRecordingStateWhenCommittedValueIsUnchanged() {
        let original = KeyboardShortcut(keyCode: 0, carbonModifiers: UInt32(cmdKey))
        let recorder = ShortcutRecorderView(shortcut: original, onChange: { _ in })
        let window = testWindow(containing: recorder)
        XCTAssertTrue(window.makeFirstResponder(recorder))
        XCTAssertTrue(recorder.beginRecordingFromClick())

        recorder.handleKey(keyCode: 0, carbonModifiers: UInt32(cmdKey))

        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.accessibilityValue() as? String, "⌘A")

        XCTAssertTrue(recorder.beginRecordingFromClick())
        recorder.shortcut = nil
        recorder.handleKey(keyCode: 51, carbonModifiers: 0)

        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.accessibilityValue() as? String, "Not Set")
    }

    func testAccessibilityPressFocusesRecorderAndBeginsRecording() {
        let recorder = ShortcutRecorderView(onChange: { _ in })
        let window = testWindow(containing: recorder)

        XCTAssertTrue(recorder.accessibilityPerformPress())
        XCTAssertTrue(window.firstResponder === recorder)
        XCTAssertTrue(recorder.isRecording)
    }

    func testRecorderConsumesKeyEquivalentOnlyWhileRecordingAndCommitsIt() {
        var changes: [KeyboardShortcut?] = []
        let recorder = ShortcutRecorderView { changes.append($0) }
        let window = testWindow(containing: recorder)

        XCTAssertFalse(
            recorder.handleKeyEquivalent(
                keyCode: 12,
                carbonModifiers: UInt32(cmdKey)
            )
        )
        XCTAssertTrue(window.makeFirstResponder(recorder))
        XCTAssertTrue(recorder.beginRecordingFromClick())

        XCTAssertTrue(
            recorder.handleKeyEquivalent(
                keyCode: 12,
                carbonModifiers: UInt32(cmdKey)
            )
        )
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(
            changes.first!,
            KeyboardShortcut(keyCode: 12, carbonModifiers: UInt32(cmdKey))
        )
    }

    private func testWindow(containing recorder: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = contentView
        contentView.addSubview(recorder)
        return window
    }
}
