import AppKit

@MainActor
public protocol PopoverFocusRequesting: AnyObject {
    func requestFocus()
}

@MainActor
public final class TranslationInputFocusController: PopoverFocusRequesting {
    private weak var responder: NSView?

    public init() {}

    public func bind(_ responder: NSView) {
        self.responder = responder
    }

    public func unbind(_ responder: NSView) {
        guard self.responder === responder else { return }
        self.responder = nil
    }

    public func requestFocus() {
        guard let responder, let window = responder.window else { return }
        window.makeFirstResponder(responder)
    }
}
