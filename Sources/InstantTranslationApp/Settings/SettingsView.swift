import AppKit
import SwiftUI
import InstantTranslationCore

enum SettingsFunctionalGroup: Hashable {
    case general
    case translationServices
    case llmPrompts
}

enum SettingsStatusEmphasis: Equatable {
    case secondary
    case success
    case error
    case critical
}

struct SettingsStatusPresentation: Equatable {
    let message: String
    let emphasis: SettingsStatusEmphasis
}

struct SettingsPresentationPolicy {
    static let functionalGroups: [SettingsFunctionalGroup] = [
        .general,
        .translationServices,
        .llmPrompts,
    ]

    let credentialAccessState: CredentialAccessState
    let saveState: SettingsSaveState
    let saveError: String?

    @MainActor
    init(model: SettingsViewModel) {
        credentialAccessState = model.credentialAccessState
        saveState = model.saveState
        saveError = model.saveError
    }

    var credentialsEditable: Bool {
        credentialAccessState == .loaded
    }

    var saveEnabled: Bool {
        credentialAccessState == .loaded && saveState != .saving
    }

    var showsCredentialReload: Bool {
        credentialAccessState == .unavailable
    }

    var credentialStatus: String? {
        guard credentialAccessState == .unavailable else { return nil }
        return "Credentials are unavailable. Reload them to edit or save settings."
    }

    var saveStatus: SettingsStatusPresentation {
        switch saveState {
        case .idle:
            SettingsStatusPresentation(message: "Ready to save.", emphasis: .secondary)
        case .saving:
            SettingsStatusPresentation(message: "Saving settings…", emphasis: .secondary)
        case .saved:
            SettingsStatusPresentation(message: "Settings saved.", emphasis: .success)
        case .failed:
            SettingsStatusPresentation(
                message: saveError ?? "Settings could not be saved. Try again.",
                emphasis: .error
            )
        case .needsAttention:
            SettingsStatusPresentation(
                message: "Some changes may not have been fully restored. Review settings and retry.",
                emphasis: .critical
            )
        }
    }

    static func connectionTestEnabled(
        provider: ProviderID,
        googleState: ConnectionTestState,
        llmState: ConnectionTestState
    ) -> Bool {
        switch provider {
        case .google:
            return googleState != .testing
        case .llm:
            return llmState != .testing
        default:
            return false
        }
    }

    static func connectionStatus(
        provider: ProviderID,
        state: ConnectionTestState
    ) -> SettingsStatusPresentation? {
        let label = provider == .google ? "Google" : "LLM"
        switch state {
        case .idle:
            return nil
        case .testing:
            return SettingsStatusPresentation(
                message: "\(label): Testing…",
                emphasis: .secondary
            )
        case .success:
            return SettingsStatusPresentation(
                message: "\(label): Connected.",
                emphasis: .success
            )
        case .failure(let error):
            return SettingsStatusPresentation(
                message: "\(label): \(connectionMessage(error))",
                emphasis: .error
            )
        }
    }

    private static func connectionMessage(_ error: TranslationProviderError) -> String {
        switch error {
        case .unconfigured: "Configuration is incomplete."
        case .invalidCredentials: "Authentication failed."
        case .rateLimited: "Rate limited."
        case .networkUnavailable: "Network unavailable."
        case .timedOut: "Timed out."
        case .insecureEndpoint: "Base URL is not allowed."
        case .invalidResponse: "Invalid response."
        case .server(let code): "Service error (\(code))."
        case .cancelled: "Cancelled."
        }
    }
}

@MainActor
struct SettingsViewActions {
    private let model: SettingsViewModel

    init(model: SettingsViewModel) {
        self.model = model
    }

    func save() async {
        do {
            try await model.save()
        } catch {
            // 可见状态由 SettingsViewModel 统一发布，界面层不展示底层错误细节。
        }
    }

    func testGoogleConnection() async {
        await model.testGoogleConnection()
    }

    func testLLMConnection() async {
        await model.testLLMConnection()
    }
}

@MainActor
public struct SettingsView: View {
    @Bindable private var model: SettingsViewModel

    public init(model: SettingsViewModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            ForEach(SettingsPresentationPolicy.functionalGroups, id: \.self) { group in
                section(for: group)
            }
            saveArea
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(minWidth: 560, minHeight: 640)
    }

    private var policy: SettingsPresentationPolicy {
        SettingsPresentationPolicy(model: model)
    }

    private var actions: SettingsViewActions {
        SettingsViewActions(model: model)
    }

    @ViewBuilder
    private func section(for group: SettingsFunctionalGroup) -> some View {
        switch group {
        case .general:
            generalSection
        case .translationServices:
            translationServicesSection
        case .llmPrompts:
            llmPromptsSection
        }
    }

    private var generalSection: some View {
        Section("General") {
            Toggle("Launch at Login", isOn: $model.launchAtLogin)
                .accessibilityLabel("Launch Instant Translation at login")
            Toggle(
                "Translate Latest Clipboard Content on Open",
                isOn: $model.translateClipboardOnOpen
            )
            .accessibilityLabel("Translate latest clipboard content when popover opens")
            LabeledContent("Global Shortcut") {
                ShortcutCaptureView(shortcut: $model.globalShortcut)
            }
        }
    }

    private var translationServicesSection: some View {
        Section("Translation Services") {
            if let status = policy.credentialStatus {
                HStack(alignment: .firstTextBaseline) {
                    Text(status)
                        .foregroundStyle(Color(nsColor: .systemRed))
                        .accessibilityLabel("Credential error: \(status)")
                    Spacer()
                    Button("Reload Credentials") {
                        model.reloadCredentials()
                    }
                    .accessibilityLabel("Reload credentials from Keychain")
                }
            }

            SecureField("Google Cloud Translation API Key", text: $model.googleAPIKey)
                .disabled(!policy.credentialsEditable)
                .accessibilityLabel("Google Cloud Translation API key")

            HStack {
                Button("Test Google Connection") {
                    Task { await actions.testGoogleConnection() }
                }
                .disabled(
                    !SettingsPresentationPolicy.connectionTestEnabled(
                        provider: .google,
                        googleState: model.googleConnectionState,
                        llmState: model.llmConnectionState
                    )
                )
                .accessibilityLabel("Test Google translation connection")
                connectionStatus(provider: .google, state: model.googleConnectionState)
            }

            TextField("LLM Base URL", text: $model.llmBaseURL)
                .accessibilityLabel("LLM Base URL")
            SecureField("LLM API Key", text: $model.llmAPIKey)
                .disabled(!policy.credentialsEditable)
                .accessibilityLabel("LLM API key")
            TextField("LLM Model", text: $model.llmModel)
                .accessibilityLabel("LLM model")

            HStack {
                Button("Test LLM Connection") {
                    Task { await actions.testLLMConnection() }
                }
                .disabled(
                    !SettingsPresentationPolicy.connectionTestEnabled(
                        provider: .llm,
                        googleState: model.googleConnectionState,
                        llmState: model.llmConnectionState
                    )
                )
                .accessibilityLabel("Test LLM connection")
                connectionStatus(provider: .llm, state: model.llmConnectionState)
            }

            Text("Connection tests send one small real request and may incur provider charges.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    "Connection test warning: tests send a small real request and may incur provider charges"
                )
        }
    }

    private var llmPromptsSection: some View {
        Section("LLM Prompts") {
            Picker("Default Preset", selection: $model.defaultPromptPresetID) {
                Text("General").tag(PromptPresetID.general)
                Text("Technology & R&D").tag(PromptPresetID.technologyAndRnD)
            }
            .accessibilityLabel("Default LLM prompt preset")

            PromptEditor(
                title: "General",
                text: $model.generalPrompt,
                restore: model.restoreGeneralPrompt
            )
            PromptEditor(
                title: "Technology & R&D",
                text: $model.technologyAndRnDPrompt,
                restore: model.restoreTechnologyAndRnDPrompt
            )
        }
    }

    private var saveArea: some View {
        HStack {
            statusText(policy.saveStatus)
                .accessibilityLabel("Save status: \(policy.saveStatus.message)")
            Spacer()
            Button("Save") {
                Task { await actions.save() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!policy.saveEnabled)
            .accessibilityLabel("Save settings")
            .accessibilityValue(policy.saveStatus.message)
        }
    }

    @ViewBuilder
    private func connectionStatus(
        provider: ProviderID,
        state: ConnectionTestState
    ) -> some View {
        if let status = SettingsPresentationPolicy.connectionStatus(
            provider: provider,
            state: state
        ) {
            statusText(status)
                .accessibilityLabel(status.message)
        }
    }

    @ViewBuilder
    private func statusText(_ status: SettingsStatusPresentation) -> some View {
        switch status.emphasis {
        case .secondary:
            Text(status.message).foregroundStyle(.secondary)
        case .success:
            Text(status.message).foregroundStyle(Color(nsColor: .systemGreen))
        case .error:
            Text(status.message).foregroundStyle(Color(nsColor: .systemRed))
        case .critical:
            Label(status.message, systemImage: "exclamationmark.triangle.fill")
                .fontWeight(.semibold)
                .foregroundStyle(Color(nsColor: .systemRed))
        }
    }
}

private struct PromptEditor: View {
    let title: String
    @Binding var text: String
    let restore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Button("Restore Default", action: restore)
                    .accessibilityLabel("Restore default \(title) prompt")
            }
            TextEditor(text: $text)
                .font(.body.monospaced())
                .frame(minHeight: 100)
                .accessibilityLabel("\(title) system prompt")
        }
    }
}
