import SwiftUI
import InstantTranslationCore
import InstantTranslationFeature

public struct TranslationView: View {
    @Bindable private var session: TranslationSession
    private let focusController: TranslationInputFocusController

    public init(
        session: TranslationSession,
        focusController: TranslationInputFocusController
    ) {
        self.session = session
        self.focusController = focusController
    }

    public var body: some View {
        VStack(spacing: 12) {
            TranslationInputField(
                text: $session.input,
                focusController: focusController,
                onSubmit: {
                    session.submit(rawText: session.input, sourceID: .manual)
                }
            )
            .frame(height: 22)
            Text("Enter to translate")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 370)
    }
}

private struct TranslationInputField: NSViewRepresentable {
    @Binding var text: String
    let focusController: TranslationInputFocusController
    let onSubmit: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Text to translate")
        focusController.bind(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        coordinator.parent.focusController.unbind(field)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TranslationInputField

        init(parent: TranslationInputField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }
            parent.text = control.stringValue
            parent.onSubmit()
            return true
        }
    }
}
