import AppKit
import Carbon.HIToolbox
import SwiftUI
import XCTest
import InstantTranslationInfrastructure
@testable import InstantTranslationApp

private typealias RecordedShortcut = InstantTranslationInfrastructure.KeyboardShortcut

@MainActor
final class ShortcutCaptureTests: XCTestCase {
    func testPolicyAcceptsModifiedOrdinaryKey() {
        let decision = ShortcutCapturePolicy.decision(
            keyCode: 0,
            carbonModifiers: UInt32(cmdKey)
        )

        XCTAssertEqual(
            decision,
            .accept(RecordedShortcut(keyCode: 0, carbonModifiers: UInt32(cmdKey)))
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
            .accept(RecordedShortcut(keyCode: 0, carbonModifiers: UInt32(cmdKey)))
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
        let shortcut = RecordedShortcut(keyCode: 0, carbonModifiers: UInt32(cmdKey))
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
                for: RecordedShortcut(
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
                    for: RecordedShortcut(
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
        var changes: [RecordedShortcut?] = []
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
            RecordedShortcut(keyCode: 0, carbonModifiers: UInt32(cmdKey))
        )
    }

    func testRecorderEscapeCancelsAndPreservesOriginalValue() {
        let original = RecordedShortcut(keyCode: 1, carbonModifiers: UInt32(optionKey))
        var changes: [RecordedShortcut?] = []
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
        let original = RecordedShortcut(keyCode: 1, carbonModifiers: UInt32(optionKey))
        var changes: [RecordedShortcut?] = []
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
        let original = RecordedShortcut(keyCode: 0, carbonModifiers: UInt32(cmdKey))
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
        var changes: [RecordedShortcut?] = []
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
            RecordedShortcut(keyCode: 12, carbonModifiers: UInt32(cmdKey))
        )
    }

    func testMouseAndKeyDownRouteModifierFlagsIntoOneCarbonShortcut() {
        var changes: [RecordedShortcut?] = []
        let recorder = ShortcutRecorderView { changes.append($0) }
        let window = testWindow(containing: recorder)
        window.makeKeyAndOrderFront(nil)

        window.sendEvent(mouseDownEvent(in: window))
        window.sendEvent(
            keyDownEvent(
                keyCode: 0,
                characters: "a",
                modifiers: [.option, .control, .shift, .capsLock, .numericPad],
                in: window
            )
        )

        XCTAssertTrue(window.firstResponder === recorder)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(
            changes.first.flatMap { $0 },
            RecordedShortcut(
                keyCode: 0,
                carbonModifiers: UInt32(optionKey | controlKey | shiftKey)
            )
        )
    }

    func testPerformKeyEquivalentConsumesCommandShortcutBeforeMenuAndCommitsOnce() {
        var changes: [RecordedShortcut?] = []
        let recorder = ShortcutRecorderView { changes.append($0) }
        let window = testWindow(containing: recorder)
        let menuTarget = MenuActionCounter()
        let menu = testMenu(keyEquivalent: "q", target: menuTarget)
        let event = keyDownEvent(
            keyCode: 12,
            characters: "q",
            modifiers: .command,
            in: window
        )
        window.makeKeyAndOrderFront(nil)
        window.sendEvent(mouseDownEvent(in: window))
        XCTAssertTrue(window.firstResponder === recorder)

        let handledByRecorder = window.performKeyEquivalent(with: event)
        if !handledByRecorder {
            _ = menu.performKeyEquivalent(with: event)
        }

        XCTAssertTrue(handledByRecorder)
        XCTAssertEqual(menuTarget.actionCount, 0)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(
            changes.first.flatMap { $0 },
            RecordedShortcut(keyCode: 12, carbonModifiers: UInt32(cmdKey))
        )
    }

    func testPerformKeyEquivalentFallsThroughToMenuWhenNotRecording() {
        var changes: [RecordedShortcut?] = []
        let recorder = ShortcutRecorderView { changes.append($0) }
        let window = testWindow(containing: recorder)
        let menuTarget = MenuActionCounter()
        let menu = testMenu(keyEquivalent: "q", target: menuTarget)
        let event = keyDownEvent(
            keyCode: 12,
            characters: "q",
            modifiers: .command,
            in: window
        )
        XCTAssertTrue(window.makeFirstResponder(recorder))

        let handledByRecorder = window.performKeyEquivalent(with: event)
        let handledByMenu = handledByRecorder ? false : menu.performKeyEquivalent(with: event)

        XCTAssertFalse(handledByRecorder)
        XCTAssertTrue(handledByMenu)
        XCTAssertEqual(menuTarget.actionCount, 1)
        XCTAssertTrue(changes.isEmpty)
    }

    func testPerformKeyEquivalentFallsThroughForNonCommandInputWhileRecording() {
        var changes: [RecordedShortcut?] = []
        let recorder = ShortcutRecorderView { changes.append($0) }
        let window = testWindow(containing: recorder)
        window.makeKeyAndOrderFront(nil)
        window.sendEvent(mouseDownEvent(in: window))

        let handled = window.performKeyEquivalent(
            with: keyDownEvent(
                keyCode: 0,
                characters: "a",
                modifiers: .option,
                in: window
            )
        )

        XCTAssertFalse(handled)
        XCTAssertTrue(recorder.isRecording)
        XCTAssertTrue(changes.isEmpty)
    }

    func testKeyDownEscapeCancelsAndPreservesShortcut() {
        let original = RecordedShortcut(keyCode: 1, carbonModifiers: UInt32(optionKey))
        var changes: [RecordedShortcut?] = []
        let recorder = ShortcutRecorderView(shortcut: original) { changes.append($0) }
        let window = testWindow(containing: recorder)
        window.makeKeyAndOrderFront(nil)
        window.sendEvent(mouseDownEvent(in: window))
        XCTAssertTrue(window.firstResponder === recorder)

        window.sendEvent(
            keyDownEvent(
                keyCode: 53,
                characters: "\u{1B}",
                modifiers: [],
                in: window
            )
        )

        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.shortcut, original)
        XCTAssertTrue(changes.isEmpty)
    }

    func testKeyDownDeleteClearsShortcutAndCommitsOnce() {
        let original = RecordedShortcut(keyCode: 1, carbonModifiers: UInt32(optionKey))
        var changes: [RecordedShortcut?] = []
        let recorder = ShortcutRecorderView(shortcut: original) { changes.append($0) }
        let window = testWindow(containing: recorder)
        window.makeKeyAndOrderFront(nil)
        window.sendEvent(mouseDownEvent(in: window))
        XCTAssertTrue(window.firstResponder === recorder)

        window.sendEvent(
            keyDownEvent(
                keyCode: 51,
                characters: "\u{7F}",
                modifiers: [],
                in: window
            )
        )

        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.shortcut)
        XCTAssertEqual(changes.count, 1)
        if changes.count == 1 {
            XCTAssertNil(changes[0])
        }
    }

    func testKeyDownModifierOnlyKeepsRecordingThroughWindowRoute() {
        var changes: [RecordedShortcut?] = []
        let recorder = ShortcutRecorderView { changes.append($0) }
        let window = testWindow(containing: recorder)
        window.makeKeyAndOrderFront(nil)
        window.sendEvent(mouseDownEvent(in: window))

        window.sendEvent(
            keyDownEvent(
                keyCode: 55,
                characters: "",
                modifiers: .command,
                in: window
            )
        )

        XCTAssertTrue(window.firstResponder === recorder)
        XCTAssertTrue(recorder.isRecording)
        XCTAssertTrue(changes.isEmpty)
    }

    func testKeyDownForwardDeleteClearsShortcutThroughWindowRoute() {
        let original = RecordedShortcut(keyCode: 1, carbonModifiers: UInt32(optionKey))
        var changes: [RecordedShortcut?] = []
        let recorder = ShortcutRecorderView(shortcut: original) { changes.append($0) }
        let window = testWindow(containing: recorder)
        window.makeKeyAndOrderFront(nil)
        window.sendEvent(mouseDownEvent(in: window))

        window.sendEvent(
            keyDownEvent(
                keyCode: 117,
                characters: "\u{F728}",
                modifiers: [],
                in: window
            )
        )

        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.shortcut)
        XCTAssertEqual(changes.count, 1)
        if changes.count == 1 {
            XCTAssertNil(changes[0])
        }
    }

    func testHostedRepresentableRoutesChangesToReplacementBindingWithoutEchoingSync() throws {
        let first = ShortcutBindingBox()
        let secondValue = RecordedShortcut(keyCode: 1, carbonModifiers: UInt32(optionKey))
        let second = ShortcutBindingBox(value: secondValue)
        let host = NSHostingView(
            rootView: ShortcutCaptureView(shortcut: first.binding)
        )
        host.frame = NSRect(x: 0, y: 0, width: 240, height: 80)
        let window = testWindow(containing: host)
        host.layoutSubtreeIfNeeded()
        let recorder = try XCTUnwrap(shortcutRecorder(in: host))

        host.rootView = ShortcutCaptureView(shortcut: second.binding)
        host.layoutSubtreeIfNeeded()
        let updatedRecorder = try XCTUnwrap(shortcutRecorder(in: host))

        XCTAssertTrue(recorder === updatedRecorder)
        XCTAssertEqual(updatedRecorder.shortcut, secondValue)
        XCTAssertEqual(first.writeCount, 0)
        XCTAssertEqual(second.writeCount, 0)

        updatedRecorder.mouseDown(with: mouseDownEvent(in: window))
        updatedRecorder.keyDown(
            with: keyDownEvent(
                keyCode: 0,
                characters: "a",
                modifiers: .command,
                in: window
            )
        )

        XCTAssertNil(first.value)
        XCTAssertEqual(first.writeCount, 0)
        XCTAssertEqual(
            second.value,
            RecordedShortcut(keyCode: 0, carbonModifiers: UInt32(cmdKey))
        )
        XCTAssertEqual(second.writeCount, 1)
    }

    private func testWindow(containing view: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = contentView
        view.frame = contentView.bounds
        contentView.addSubview(view)
        return window
    }

    private func shortcutRecorder(in view: NSView) -> ShortcutRecorderView? {
        if let recorder = view as? ShortcutRecorderView {
            return recorder
        }
        return view.subviews.lazy.compactMap(shortcutRecorder(in:)).first
    }

    private func mouseDownEvent(in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )!
    }

    private func keyDownEvent(
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags,
        in window: NSWindow
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    private func testMenu(keyEquivalent: String, target: MenuActionCounter) -> NSMenu {
        let menu = NSMenu()
        let item = NSMenuItem(
            title: "Test Action",
            action: #selector(MenuActionCounter.performMenuAction(_:)),
            keyEquivalent: keyEquivalent
        )
        item.keyEquivalentModifierMask = .command
        item.target = target
        menu.addItem(item)
        return menu
    }
}

@MainActor
private final class MenuActionCounter: NSObject {
    private(set) var actionCount = 0

    @objc func performMenuAction(_ sender: Any?) {
        actionCount += 1
    }
}

@MainActor
private final class ShortcutBindingBox {
    var value: RecordedShortcut?
    private(set) var writeCount = 0

    init(value: RecordedShortcut? = nil) {
        self.value = value
    }

    var binding: Binding<RecordedShortcut?> {
        Binding(
            get: { self.value },
            set: {
                self.writeCount += 1
                self.value = $0
            }
        )
    }
}
