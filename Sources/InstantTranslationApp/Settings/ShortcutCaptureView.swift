import AppKit
import Carbon.HIToolbox
import SwiftUI
import InstantTranslationInfrastructure

enum ShortcutCaptureDecision: Equatable {
    case ignore
    case reject
    case cancel
    case clear
    case accept(InstantTranslationInfrastructure.KeyboardShortcut)
}

enum ShortcutCaptureEffect: Equatable {
    case none
    case commit(InstantTranslationInfrastructure.KeyboardShortcut?)
}

struct ShortcutCaptureSession {
    private(set) var isRecording = false

    mutating func begin() {
        isRecording = true
    }

    mutating func cancel() {
        isRecording = false
    }

    mutating func handle(_ decision: ShortcutCaptureDecision) -> ShortcutCaptureEffect {
        guard isRecording else {
            return .none
        }

        switch decision {
        case .ignore, .reject:
            return .none
        case .cancel:
            cancel()
            return .none
        case .clear:
            cancel()
            return .commit(nil)
        case .accept(let shortcut):
            cancel()
            return .commit(shortcut)
        }
    }
}

enum ShortcutCapturePolicy {
    private static let modifierKeyCodes: Set<UInt16> = [
        54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
    ]
    private static let supportedModifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)
    private static let keyLabels: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`",
        51: "⌫", 53: "⎋", 65: "Keypad .", 67: "Keypad *", 69: "Keypad +",
        71: "Clear", 75: "Keypad /", 76: "Keypad ↩", 78: "Keypad -",
        81: "Keypad =", 82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2",
        85: "Keypad 3", 86: "Keypad 4", 87: "Keypad 5", 88: "Keypad 6",
        89: "Keypad 7", 91: "Keypad 8", 92: "Keypad 9", 96: "F5", 97: "F6",
        98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 109: "F10",
        111: "F12", 114: "Help", 115: "Home", 116: "Page Up", 117: "⌦",
        118: "F4", 119: "End", 120: "F2", 121: "Page Down", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    static func decision(
        keyCode: UInt16,
        carbonModifiers: UInt32
    ) -> ShortcutCaptureDecision {
        if keyCode == 53 {
            return .cancel
        }
        if keyCode == 51 || keyCode == 117 {
            return .clear
        }
        if modifierKeyCodes.contains(keyCode) {
            return .ignore
        }

        let modifiers = carbonModifiers & supportedModifiers
        guard modifiers != 0 else {
            return .reject
        }

        return .accept(
            InstantTranslationInfrastructure.KeyboardShortcut(
                keyCode: UInt32(keyCode),
                carbonModifiers: modifiers
            )
        )
    }

    static func label(
        for shortcut: InstantTranslationInfrastructure.KeyboardShortcut?
    ) -> String {
        guard let shortcut else {
            return "Not Set"
        }

        var value = ""
        if shortcut.carbonModifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if shortcut.carbonModifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if shortcut.carbonModifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if shortcut.carbonModifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        return value + (keyLabels[shortcut.keyCode] ?? "Key \(shortcut.keyCode)")
    }
}

@MainActor
private final class ShortcutChangeSink {
    typealias Handler = (InstantTranslationInfrastructure.KeyboardShortcut?) -> Void

    private var handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func update(handler: @escaping Handler) {
        self.handler = handler
    }

    func send(_ shortcut: InstantTranslationInfrastructure.KeyboardShortcut?) {
        handler(shortcut)
    }
}

@MainActor
public struct ShortcutCaptureView: NSViewRepresentable {
    @Binding private var shortcut: InstantTranslationInfrastructure.KeyboardShortcut?

    public init(
        shortcut: Binding<InstantTranslationInfrastructure.KeyboardShortcut?>
    ) {
        _shortcut = shortcut
    }

    public func makeNSView(context: Context) -> ShortcutRecorderView {
        let binding = $shortcut
        return ShortcutRecorderView(shortcut: shortcut) {
            binding.wrappedValue = $0
        }
    }

    public func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        let binding = $shortcut
        // NSView 会跨 SwiftUI 更新复用；先替换写回目标，避免继续持有首次 Binding。
        view.updateChangeHandler { binding.wrappedValue = $0 }
        view.shortcut = shortcut
    }
}

@MainActor
public final class ShortcutRecorderView: NSView {
    public var shortcut: InstantTranslationInfrastructure.KeyboardShortcut? {
        didSet {
            guard oldValue != shortcut else { return }
            updatePresentation()
        }
    }

    private var session = ShortcutCaptureSession()
    private let changeSink: ShortcutChangeSink

    var isRecording: Bool { session.isRecording }

    public override var acceptsFirstResponder: Bool { true }
    public override var intrinsicContentSize: NSSize { NSSize(width: 180, height: 28) }
    public override var focusRingMaskBounds: NSRect { bounds }

    init(
        shortcut: InstantTranslationInfrastructure.KeyboardShortcut? = nil,
        onChange: @escaping (InstantTranslationInfrastructure.KeyboardShortcut?) -> Void
    ) {
        self.shortcut = shortcut
        changeSink = ShortcutChangeSink(handler: onChange)
        super.init(frame: .zero)
        focusRingType = .exterior
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Keyboard shortcut")
        updateAccessibilityText()
    }

    required init?(coder: NSCoder) { nil }

    @discardableResult
    func beginRecordingFromClick() -> Bool {
        guard window?.firstResponder === self else {
            return false
        }
        session.begin()
        updatePresentation()
        return true
    }

    func handleKey(keyCode: UInt16, carbonModifiers: UInt32) {
        let wasRecording = session.isRecording
        let effect = session.handle(
            ShortcutCapturePolicy.decision(
                keyCode: keyCode,
                carbonModifiers: carbonModifiers
            )
        )

        switch effect {
        case .none:
            if wasRecording != session.isRecording {
                updatePresentation()
            }
        case .commit(let value):
            if shortcut == value {
                updatePresentation()
            } else {
                shortcut = value
            }
            changeSink.send(value)
        }
    }

    fileprivate func updateChangeHandler(
        _ handler: @escaping ShortcutChangeSink.Handler
    ) {
        changeSink.update(handler: handler)
    }

    func handleKeyEquivalent(keyCode: UInt16, carbonModifiers: UInt32) -> Bool {
        guard session.isRecording else { return false }
        handleKey(keyCode: keyCode, carbonModifiers: carbonModifiers)
        return true
    }

    func cancelRecording() {
        guard session.isRecording else { return }
        session.cancel()
        updatePresentation()
    }

    public override func mouseDown(with event: NSEvent) {
        guard window?.makeFirstResponder(self) == true else { return }
        beginRecordingFromClick()
    }

    public override func keyDown(with event: NSEvent) {
        guard session.isRecording else {
            super.keyDown(with: event)
            return
        }
        handleKey(
            keyCode: event.keyCode,
            carbonModifiers: Self.carbonModifiers(from: event.modifierFlags)
        )
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        return handleKeyEquivalent(
            keyCode: event.keyCode,
            carbonModifiers: Self.carbonModifiers(from: event.modifierFlags)
        ) || super.performKeyEquivalent(with: event)
    }

    public override func accessibilityPerformPress() -> Bool {
        guard window?.makeFirstResponder(self) == true else { return false }
        return beginRecordingFromClick()
    }

    public override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder { needsDisplay = true }
        return becameFirstResponder
    }

    public override func resignFirstResponder() -> Bool {
        cancelRecording()
        let resignedFirstResponder = super.resignFirstResponder()
        if resignedFirstResponder { needsDisplay = true }
        return resignedFirstResponder
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let window {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didResignKeyNotification,
                object: window
            )
        }
        cancelRecording()
        super.viewWillMove(toWindow: newWindow)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidResignKey),
                name: NSWindow.didResignKeyNotification,
                object: window
            )
        }
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    public override func drawFocusRingMask() {
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1),
            xRadius: 6,
            yRadius: 6
        ).fill()
    }

    public override func draw(_ dirtyRect: NSRect) {
        let borderRect = bounds.insetBy(dx: 1, dy: 1)
        let background = NSBezierPath(roundedRect: borderRect, xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        background.fill()

        let focused = window?.firstResponder === self
        (focused ? NSColor.keyboardFocusIndicatorColor : NSColor.separatorColor).setStroke()
        background.lineWidth = focused ? 2 : 1
        background.stroke()

        let label = isRecording ? "Press shortcut…" : ShortcutCapturePolicy.label(for: shortcut)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = label.size(withAttributes: attributes)
        label.draw(
            at: NSPoint(x: 9, y: (bounds.height - size.height) / 2),
            withAttributes: attributes
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowDidResignKey() {
        cancelRecording()
    }

    private func updatePresentation() {
        needsDisplay = true
        updateAccessibilityText()
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    private func updateAccessibilityText() {
        if isRecording {
            setAccessibilityValue("Press shortcut")
            setAccessibilityHelp(
                "Press a shortcut with Command, Option, Control, or Shift. "
                    + "Escape cancels; Delete clears."
            )
        } else {
            setAccessibilityValue(ShortcutCapturePolicy.label(for: shortcut))
            setAccessibilityHelp("Click to record a keyboard shortcut.")
        }
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }
}
