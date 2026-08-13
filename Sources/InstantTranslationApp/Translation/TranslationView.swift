import SwiftUI
import InstantTranslationCore
import InstantTranslationFeature

@MainActor
public struct TranslationView: View {
    @Bindable private var session: TranslationSession
    @Bindable private var appearance: ProviderAppearance
    @Bindable private var availability: ProviderAvailability
    @State private var copyController: CopyController
    private let focusController: TranslationInputFocusController
    private let openSettings: @MainActor () -> Void

    public init(
        session: TranslationSession,
        appearance: ProviderAppearance,
        availability: ProviderAvailability,
        focusController: TranslationInputFocusController,
        openSettings: @escaping @MainActor () -> Void = {
            NotificationCenter.default.post(
                name: .openInstantTranslationSettings,
                object: nil
            )
        }
    ) {
        self.session = session
        self.appearance = appearance
        self.availability = availability
        self.focusController = focusController
        self.openSettings = openSettings
        _copyController = State(initialValue: CopyController())
    }

    private var shownDirection: TranslationDirection {
        if let request = session.activeRequest {
            return TranslationDirection(
                source: request.sourceLanguage,
                target: request.targetLanguage
            )
        }
        return DirectionResolver().resolve(session.input)
    }

    private var emptyStateReason: TranslationEmptyStateReason? {
        TranslationResultsPresentation.emptyStateReason(
            configured: availability.configuredProviderIDs,
            enabled: session.enabledProviderIDs
        )
    }

    public var body: some View {
        VStack(spacing: 10) {
            DirectionControl(direction: shownDirection) {
                session.swapDirectionAndResubmit()
            }
            TranslationInputField(
                text: $session.input,
                focusController: focusController,
                onSubmit: {
                    session.submit(rawText: session.input, sourceID: .manual)
                }
            )
            .frame(height: 24)
            HStack {
                if session.requiresManualClipboardConfirmation {
                    Text("Clipboard text exceeds 500 characters. Press Enter to translate.")
                }
                Spacer()
                Text("Enter to translate")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let emptyStateReason {
                TranslationEmptyStateView(
                    reason: emptyStateReason,
                    openSettings: openSettings
                )
            } else {
                ForEach(
                    TranslationResultsPresentation.visibleProviderIDs(
                        enabled: session.enabledProviderIDs
                    ),
                    id: \.self
                ) { providerID in
                    ResultCardView(
                        providerID: providerID,
                        state: session.states[providerID] ?? .idle,
                        llmBrand: appearance.llmBrand,
                        isConfigured: availability.configuredProviderIDs.contains(providerID),
                        copyController: copyController,
                        retry: { session.retry(providerID: providerID) },
                        openSettings: openSettings
                    )
                }
            }
        }
        .padding(14)
        .frame(width: 370)
        .background(.clear)
        .onAppear {
            // SwiftUI 出现时先请求一次；popover 每次展示后仍由 AppKit 桥再次确保焦点。
            focusController.requestFocus()
        }
    }
}

private struct DirectionControl: View {
    let direction: TranslationDirection
    let swap: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Text("\(shortName(direction.source)) → \(shortName(direction.target))")
            Button(action: swap) {
                Image(systemName: "arrow.left.arrow.right")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Swap translation direction")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func shortName(_ language: LanguageID) -> String {
        language == .simplifiedChinese ? "中" : "英"
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
