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

/// 设置页中由用户可感知或操作的控件。真实视图与测试共用这份稳定标识，
/// 避免依赖 SwiftUI 私有的 AppKit 视图层级。
enum SettingsControlID: String, CaseIterable, Hashable {
    case launchAtLogin
    case clipboardOnOpen
    case globalShortcut
    case credentialStatus
    case reloadCredentials
    case googleAPIKey
    case googleTest
    case googleStatus
    case llmBaseURL
    case llmAPIKey
    case llmModel
    case llmTest
    case llmStatus
    case connectionWarning
    case promptPreset
    case generalPrompt
    case restoreGeneralPrompt
    case technologyPrompt
    case restoreTechnologyPrompt
    case saveStatus
    case save
}

struct SettingsControlDescriptor: Identifiable, Equatable {
    let id: SettingsControlID
    let group: SettingsFunctionalGroup?
    let accessibilityLabel: String
    let value: String?
    let status: SettingsStatusPresentation?
    let isVisible: Bool
    let isEnabled: Bool
}

/// 这是设置页的渲染与动作注册表。`SettingsView` 直接读取它来决定控件状态并分派动作，
/// 因此测试这里等价于验证真实视图使用的契约，而不是复制一份测试专用策略。
@MainActor
struct SettingsViewRegistry {
    private let model: SettingsViewModel

    init(model: SettingsViewModel) {
        self.model = model
    }

    var groups: [SettingsFunctionalGroup] {
        SettingsPresentationPolicy.functionalGroups
    }

    var controls: [SettingsControlDescriptor] {
        // 显式清单同时决定真实渲染顺序；遗漏条目会被完整性测试捕获。
        let orderedIDs: [SettingsControlID] = [
            .launchAtLogin, .clipboardOnOpen, .globalShortcut,
            .credentialStatus, .reloadCredentials, .googleAPIKey, .googleTest,
            .googleStatus, .llmBaseURL, .llmAPIKey, .llmModel, .llmTest,
            .llmStatus, .connectionWarning,
            .promptPreset, .generalPrompt, .restoreGeneralPrompt,
            .technologyPrompt, .restoreTechnologyPrompt,
            .saveStatus, .save,
        ]
        return orderedIDs.map(makeDescriptor)
    }

    func control(_ id: SettingsControlID) -> SettingsControlDescriptor {
        guard let descriptor = controls.first(where: { $0.id == id }) else {
            preconditionFailure("Missing settings control descriptor: \(id.rawValue)")
        }
        return descriptor
    }

    func perform(_ id: SettingsControlID) async {
        let actions = SettingsViewActions(model: model)
        switch id {
        case .reloadCredentials:
            model.reloadCredentials()
        case .googleTest:
            await actions.testGoogleConnection()
        case .llmTest:
            await actions.testLLMConnection()
        case .restoreGeneralPrompt:
            model.restoreGeneralPrompt()
        case .restoreTechnologyPrompt:
            model.restoreTechnologyAndRnDPrompt()
        case .save:
            await actions.save()
        default:
            break
        }
    }

    private func makeDescriptor(_ id: SettingsControlID) -> SettingsControlDescriptor {
        let policy = SettingsPresentationPolicy(model: model)
        let common = descriptorDefaults(for: id)
        switch id {
        case .credentialStatus:
            return common.replacing(
                value: policy.credentialStatus,
                isVisible: policy.credentialStatus != nil
            )
        case .reloadCredentials:
            return common.replacing(isVisible: policy.showsCredentialReload)
        case .googleAPIKey, .llmAPIKey:
            return common.replacing(isEnabled: policy.credentialsEditable)
        case .googleTest:
            return common.replacing(
                isEnabled: SettingsPresentationPolicy.connectionTestEnabled(
                    provider: .google,
                    googleState: model.googleConnectionState,
                    llmState: model.llmConnectionState
                )
            )
        case .googleStatus:
            let status = SettingsPresentationPolicy.connectionStatus(
                provider: .google,
                state: model.googleConnectionState
            )
            return common.replacing(
                value: status?.message,
                status: status,
                isVisible: status != nil
            )
        case .llmTest:
            return common.replacing(
                isEnabled: SettingsPresentationPolicy.connectionTestEnabled(
                    provider: .llm,
                    googleState: model.googleConnectionState,
                    llmState: model.llmConnectionState
                )
            )
        case .llmStatus:
            let status = SettingsPresentationPolicy.connectionStatus(
                provider: .llm,
                state: model.llmConnectionState
            )
            return common.replacing(
                value: status?.message,
                status: status,
                isVisible: status != nil
            )
        case .saveStatus:
            return common.replacing(
                value: policy.saveStatus.message,
                status: policy.saveStatus
            )
        case .save:
            return common.replacing(
                value: policy.saveStatus.message,
                isEnabled: policy.saveEnabled
            )
        default:
            return common
        }
    }

    private func descriptorDefaults(for id: SettingsControlID) -> SettingsControlDescriptor {
        let metadata: (group: SettingsFunctionalGroup?, accessibilityLabel: String)
        switch id {
        case .launchAtLogin:
            metadata = (.general, "Launch Instant Translation at login")
        case .clipboardOnOpen:
            metadata = (
                .general,
                "Translate latest clipboard content when popover opens"
            )
        case .globalShortcut:
            metadata = (.general, "Global translation shortcut")
        case .credentialStatus:
            metadata = (.translationServices, "Credential status")
        case .reloadCredentials:
            metadata = (.translationServices, "Reload credentials from Keychain")
        case .googleAPIKey:
            metadata = (.translationServices, "Google Cloud Translation API key")
        case .googleTest:
            metadata = (.translationServices, "Test Google translation connection")
        case .googleStatus:
            metadata = (.translationServices, "Google connection status")
        case .llmBaseURL:
            metadata = (.translationServices, "LLM Base URL")
        case .llmAPIKey:
            metadata = (.translationServices, "LLM API key")
        case .llmModel:
            metadata = (.translationServices, "LLM model")
        case .llmTest:
            metadata = (.translationServices, "Test LLM connection")
        case .llmStatus:
            metadata = (.translationServices, "LLM connection status")
        case .connectionWarning:
            metadata = (
                .translationServices,
                "Connection test warning: tests send a small real request and may incur provider charges"
            )
        case .promptPreset:
            metadata = (.llmPrompts, "Default LLM prompt preset")
        case .generalPrompt:
            metadata = (.llmPrompts, "General system prompt")
        case .restoreGeneralPrompt:
            metadata = (.llmPrompts, "Restore default General prompt")
        case .technologyPrompt:
            metadata = (.llmPrompts, "Technology & R&D system prompt")
        case .restoreTechnologyPrompt:
            metadata = (.llmPrompts, "Restore default Technology & R&D prompt")
        case .saveStatus:
            metadata = (nil, "Save status")
        case .save:
            metadata = (nil, "Save settings")
        }
        return SettingsControlDescriptor(
            id: id,
            group: metadata.group,
            accessibilityLabel: metadata.accessibilityLabel,
            value: nil,
            status: nil,
            isVisible: id != .credentialStatus
                && id != .reloadCredentials
                && id != .googleStatus
                && id != .llmStatus,
            isEnabled: true
        )
    }
}

private extension SettingsControlDescriptor {
    func replacing(
        value: String? = nil,
        status: SettingsStatusPresentation? = nil,
        isVisible: Bool? = nil,
        isEnabled: Bool? = nil
    ) -> SettingsControlDescriptor {
        SettingsControlDescriptor(
            id: id,
            group: group,
            accessibilityLabel: accessibilityLabel,
            value: value ?? self.value,
            status: status ?? self.status,
            isVisible: isVisible ?? self.isVisible,
            isEnabled: isEnabled ?? self.isEnabled
        )
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
            ForEach(registry.groups, id: \.self) { group in
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

    private var registry: SettingsViewRegistry {
        SettingsViewRegistry(model: model)
    }

    @ViewBuilder
    private func section(for group: SettingsFunctionalGroup) -> some View {
        switch group {
        case .general:
            Section("General") {
                controls(in: group)
            }
        case .translationServices:
            Section("Translation Services") {
                controls(in: group)
            }
        case .llmPrompts:
            Section("LLM Prompts") {
                controls(in: group)
            }
        }
    }

    private func controls(in group: SettingsFunctionalGroup) -> some View {
        ForEach(
            registry.controls.filter { $0.group == group && $0.isVisible }
        ) { descriptor in
            controlRow(descriptor)
        }
    }

    @ViewBuilder
    private func controlRow(_ descriptor: SettingsControlDescriptor) -> some View {
        switch descriptor.id {
        case .launchAtLogin:
            Toggle("Launch at Login", isOn: $model.launchAtLogin)
                .accessibilityLabel(descriptor.accessibilityLabel)
        case .clipboardOnOpen:
            Toggle(
                "Translate Latest Clipboard Content on Open",
                isOn: $model.translateClipboardOnOpen
            )
            .accessibilityLabel(descriptor.accessibilityLabel)
        case .globalShortcut:
            LabeledContent("Global Shortcut") {
                ShortcutCaptureView(shortcut: $model.globalShortcut)
            }
            .accessibilityLabel(descriptor.accessibilityLabel)
        case .credentialStatus:
            if let status = descriptor.value {
                Text(status)
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .accessibilityLabel(descriptor.accessibilityLabel)
                    .accessibilityValue(status)
            }
        case .reloadCredentials:
            Button("Reload Credentials") {
                Task { await registry.perform(descriptor.id) }
            }
            .disabled(!descriptor.isEnabled)
            .accessibilityLabel(descriptor.accessibilityLabel)
        case .googleAPIKey:
            SecureField("Google Cloud Translation API Key", text: $model.googleAPIKey)
                .disabled(!descriptor.isEnabled)
                .accessibilityLabel(descriptor.accessibilityLabel)
        case .googleTest:
            Button("Test Google Connection") {
                Task { await registry.perform(descriptor.id) }
            }
            .disabled(!descriptor.isEnabled)
            .accessibilityLabel(descriptor.accessibilityLabel)
        case .googleStatus, .llmStatus:
            if let status = descriptor.status {
                statusText(status)
                    .accessibilityLabel(descriptor.accessibilityLabel)
                    .accessibilityValue(descriptor.value ?? "")
            }
        case .llmBaseURL:
            TextField("LLM Base URL", text: $model.llmBaseURL)
                .accessibilityLabel(descriptor.accessibilityLabel)
        case .llmAPIKey:
            SecureField("LLM API Key", text: $model.llmAPIKey)
                .disabled(!descriptor.isEnabled)
                .accessibilityLabel(descriptor.accessibilityLabel)
        case .llmModel:
            TextField("LLM Model", text: $model.llmModel)
                .accessibilityLabel(descriptor.accessibilityLabel)
        case .llmTest:
            Button("Test LLM Connection") {
                Task { await registry.perform(descriptor.id) }
            }
            .disabled(!descriptor.isEnabled)
            .accessibilityLabel(descriptor.accessibilityLabel)
        case .connectionWarning:
            Text("Connection tests send one small real request and may incur provider charges.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(descriptor.accessibilityLabel)
        case .promptPreset:
            Picker("Default Preset", selection: $model.defaultPromptPresetID) {
                Text("General").tag(PromptPresetID.general)
                Text("Technology & R&D").tag(PromptPresetID.technologyAndRnD)
            }
            .accessibilityLabel(descriptor.accessibilityLabel)
        case .generalPrompt:
            TextEditor(text: $model.generalPrompt)
                .font(.body.monospaced())
                .frame(minHeight: 100)
                .accessibilityLabel(descriptor.accessibilityLabel)
        case .restoreGeneralPrompt:
            Button("Restore General Default") {
                Task { await registry.perform(descriptor.id) }
            }
            .accessibilityLabel(descriptor.accessibilityLabel)
        case .technologyPrompt:
            TextEditor(text: $model.technologyAndRnDPrompt)
                .font(.body.monospaced())
                .frame(minHeight: 100)
                .accessibilityLabel(descriptor.accessibilityLabel)
        case .restoreTechnologyPrompt:
            Button("Restore Technology & R&D Default") {
                Task { await registry.perform(descriptor.id) }
            }
            .accessibilityLabel(descriptor.accessibilityLabel)
        case .saveStatus, .save:
            EmptyView()
        }
    }

    private var saveArea: some View {
        let saveStatus = control(.saveStatus)
        let save = control(.save)
        return HStack {
            statusText(saveStatus.status ?? policy.saveStatus)
                .accessibilityLabel(saveStatus.accessibilityLabel)
                .accessibilityValue(saveStatus.value ?? "")
            Spacer()
            Button("Save") {
                Task { await registry.perform(.save) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!save.isEnabled)
            .accessibilityLabel(save.accessibilityLabel)
            .accessibilityValue(save.value ?? "")
        }
    }

    private func control(_ id: SettingsControlID) -> SettingsControlDescriptor {
        registry.control(id)
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
