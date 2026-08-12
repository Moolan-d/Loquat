import SwiftUI
import InstantTranslationCore
import InstantTranslationFeature

public struct TranslationView: View {
    @Bindable private var session: TranslationSession

    public init(session: TranslationSession) {
        self.session = session
    }

    public var body: some View {
        VStack(spacing: 12) {
            TextField("", text: $session.input)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    session.submit(rawText: session.input, sourceID: .manual)
                }
                .accessibilityLabel("Text to translate")
            Text("Enter to translate")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 370)
    }
}
