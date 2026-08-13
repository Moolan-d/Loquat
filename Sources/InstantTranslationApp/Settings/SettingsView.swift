import AppKit
import SwiftUI
import InstantTranslationCore
import InstantTranslationInfrastructure

enum SettingsFunctionalGroup: Hashable {
    case general
    case translationServices
    case googleService
    case llmService
    case llmPrompts

    /// 二级模块的标题、开关与品牌图标成对出现，放在一起避免视图里散落映射。
    var providerSwitch: (title: String, controlID: SettingsControlID, providerID: ProviderID)? {
        switch self {
        case .googleService: ("Google", .googleEnabled, .google)
        case .llmService: ("LLM", .llmEnabled, .llm)
        default: nil
        }
    }
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
        .googleService,
        .llmService,
        .llmPrompts,
    ]

    /// Google 与 LLM 是 Translation Services 的二级模块，不再各自成节：
    /// 独立成节时关闭分组会让空 Section 与下一个节标题挤在一起，标题被压小。
    static let sectionGroups: [SettingsFunctionalGroup] = [
        .general,
        .translationServices,
        .llmPrompts,
    ]

    /// 二级模块按此顺序内嵌在 Translation Services 里。
    static let providerGroups: [SettingsFunctionalGroup] = [
        .googleService,
        .llmService,
    ]

    /// 卡片副标题直接说明开关的后果：关闭只是不在翻译窗口出现，配置原样保留。
    static func providerVisibilityCaption(isVisible: Bool) -> String {
        isVisible
            ? "Shown in the translation window"
            : "Hidden from the translation window — settings are kept"
    }

    /// 二级模块的字段标签由卡片统一渲染成一列以便对齐，控件自带的标签用 labelsHidden 收起。
    /// 返回 nil 表示该控件横跨整行（按钮、状态行），没有标签列。
    static func providerFieldLabel(_ id: SettingsControlID) -> String? {
        switch id {
        case .googleAPIKey, .llmAPIKey: "API Key"
        case .llmBaseURL: "Base URL"
        case .llmModel: "Model"
        default: nil
        }
    }

    let credentialAccessState: CredentialAccessState
    let saveState: SettingsSaveState
    let saveError: String?
    let googleProviderEnabled: Bool
    let llmProviderEnabled: Bool

    @MainActor
    init(model: SettingsViewModel) {
        credentialAccessState = model.credentialAccessState
        saveState = model.saveState
        saveError = model.saveError
        googleProviderEnabled = model.googleProviderEnabled
        llmProviderEnabled = model.llmProviderEnabled
    }

    /// 分组开关只控制条目与配置项的可见性；关闭时保留模型里的凭据与参数，保存后依然回写原值。
    func showsDetails(for group: SettingsFunctionalGroup) -> Bool {
        switch group {
        case .googleService: googleProviderEnabled
        case .llmService: llmProviderEnabled
        default: true
        }
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
    case clipboardOnShortcut
    case globalShortcut
    case credentialStatus
    case reloadCredentials
    case connectionWarning
    case googleEnabled
    case googleAPIKey
    case googleTest
    case googleStatus
    case llmEnabled
    case llmBaseURL
    case llmAPIKey
    case llmModel
    case llmTest
    case llmStatus
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

    var sectionGroups: [SettingsFunctionalGroup] {
        SettingsPresentationPolicy.sectionGroups
    }

    var providerGroups: [SettingsFunctionalGroup] {
        SettingsPresentationPolicy.providerGroups
    }

    var controls: [SettingsControlDescriptor] {
        // 显式清单同时决定真实渲染顺序；遗漏条目会被完整性测试捕获。
        let orderedIDs: [SettingsControlID] = [
            .launchAtLogin, .globalShortcut, .clipboardOnShortcut,
            .credentialStatus, .reloadCredentials, .connectionWarning,
            .googleEnabled, .googleAPIKey, .googleTest, .googleStatus,
            .llmEnabled, .llmBaseURL, .llmAPIKey, .llmModel, .llmTest, .llmStatus,
            .promptPreset, .generalPrompt, .restoreGeneralPrompt,
            .technologyPrompt, .restoreTechnologyPrompt,
            .saveStatus, .save,
        ]
        return orderedIDs.map(makeDescriptor)
    }

    /// 分组标题里的开关独立渲染，不参与分组内容列表。
    static let headerControlIDs: Set<SettingsControlID> = [.googleEnabled, .llmEnabled]

    func bodyControls(in group: SettingsFunctionalGroup) -> [SettingsControlDescriptor] {
        controls.filter {
            $0.group == group
                && $0.isVisible
                && !Self.headerControlIDs.contains($0.id)
        }
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
        // 分组开关关闭时整组配置项隐藏，但模型里的值原样保留。
        let collapsed = common.group.map { !policy.showsDetails(for: $0) } ?? false
        guard !collapsed || Self.headerControlIDs.contains(id) else {
            return common.replacing(isVisible: false)
        }
        switch id {
        case .credentialStatus:
            return common.replacing(
                value: policy.credentialStatus,
                isVisible: policy.credentialStatus != nil
            )
        case .reloadCredentials:
            return common.replacing(isVisible: policy.showsCredentialReload)
        case .clipboardOnShortcut:
            // 剪贴板读取是快捷键的从属子设置：未录快捷键时整行隐藏。
            return common.replacing(isVisible: model.globalShortcut != nil)
        case .googleEnabled:
            return common.replacing(value: policy.googleProviderEnabled ? "On" : "Off")
        case .llmEnabled:
            return common.replacing(value: policy.llmProviderEnabled ? "On" : "Off")
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
            metadata = (.general, "Launch Loquat at login")
        case .clipboardOnShortcut:
            metadata = (
                .general,
                "Translate clipboard when opened by shortcut"
            )
        case .globalShortcut:
            metadata = (.general, "Global translation shortcut")
        case .credentialStatus:
            metadata = (.translationServices, "Credential status")
        case .reloadCredentials:
            metadata = (.translationServices, "Reload credentials from Keychain")
        case .connectionWarning:
            metadata = (
                .translationServices,
                "Connection test warning: tests send a small real request and may incur provider charges"
            )
        case .googleEnabled:
            metadata = (.googleService, "Show Google in the translation window")
        case .googleAPIKey:
            metadata = (.googleService, "Google Cloud Translation API key")
        case .googleTest:
            metadata = (.googleService, "Test Google translation connection")
        case .googleStatus:
            metadata = (.googleService, "Google connection status")
        case .llmEnabled:
            metadata = (.llmService, "Show LLM in the translation window")
        case .llmBaseURL:
            metadata = (.llmService, "LLM Base URL")
        case .llmAPIKey:
            metadata = (.llmService, "LLM API key")
        case .llmModel:
            metadata = (.llmService, "LLM model")
        case .llmTest:
            metadata = (.llmService, "Test LLM connection")
        case .llmStatus:
            metadata = (.llmService, "LLM connection status")
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
            ForEach(registry.sectionGroups, id: \.self) { group in
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
                providerCards
                // 连接测试提示放在卡片之后，作为 Test Connection 按钮的脚注而不是节首的孤立说明。
                controls(in: group)
            }
        case .llmPrompts:
            Section("LLM Prompts") {
                controls(in: group)
            }
        case .googleService, .llmService:
            // 二级模块由 translationServices 内嵌渲染，不作为独立节出现。
            EmptyView()
        }
    }

    /// 两个二级模块整体只占 Form 的一行：Form 的行分隔线一旦穿过卡片，
    /// 卡片边界就会被切断，层级又退回"平级行"的观感。
    private var providerCards: some View {
        VStack(spacing: 12) {
            ForEach(registry.providerGroups, id: \.self) { group in
                providerCard(group)
            }
        }
        .padding(.vertical, 4)
    }

    /// 层级靠容器建立而不是靠字重：section 卡片是外层，provider 是嵌在其中自带描边的一层，
    /// 卡片内再用分隔线把标题区与字段区分开，于是"模块 → 子模块 → 字段"三层各有边界。
    @ViewBuilder
    private func providerCard(_ group: SettingsFunctionalGroup) -> some View {
        if let providerSwitch = group.providerSwitch {
            let isVisible = policy.showsDetails(for: group)
            let bodyControls = registry.bodyControls(in: group)
            VStack(alignment: .leading, spacing: 12) {
                providerCardHeader(
                    title: providerSwitch.title,
                    providerID: providerSwitch.providerID,
                    descriptor: control(providerSwitch.controlID),
                    isVisible: isVisible,
                    isOn: providerBinding(group)
                )
                if !bodyControls.isEmpty {
                    Divider()
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        ForEach(bodyControls) { descriptor in
                            providerFieldRow(descriptor)
                        }
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    // 关闭的模块整体减淡后退，但仍保留完整边界，不会看起来像被删掉了。
                    .fill(Color.primary.opacity(isVisible ? 0.05 : 0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isVisible ? 0.10 : 0.06))
            )
        }
    }

    private func providerCardHeader(
        title: String,
        providerID: ProviderID,
        descriptor: SettingsControlDescriptor,
        isVisible: Bool,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 10) {
            // 图标与翻译窗口的卡片同源，设置项与它控制的那张卡片因此能对上号。
            ProviderIconView(
                providerID: providerID,
                llmBrand: ProviderBrandResolver.resolve(baseURL: model.llmBaseURL)
            )
            .opacity(isVisible ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(isVisible ? .primary : .secondary)
                Text(SettingsPresentationPolicy.providerVisibilityCaption(isVisible: isVisible))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(descriptor.accessibilityLabel)
                .accessibilityValue(descriptor.value ?? "")
        }
    }

    @ViewBuilder
    private func providerFieldRow(_ descriptor: SettingsControlDescriptor) -> some View {
        if let label = SettingsPresentationPolicy.providerFieldLabel(descriptor.id) {
            GridRow(alignment: .firstTextBaseline) {
                Text(label)
                    .foregroundStyle(.secondary)
                controlRow(descriptor)
            }
        } else {
            GridRow {
                controlRow(descriptor)
                    .gridCellColumns(2)
            }
        }
    }

    private func providerBinding(_ group: SettingsFunctionalGroup) -> Binding<Bool> {
        switch group {
        case .googleService: $model.googleProviderEnabled
        case .llmService: $model.llmProviderEnabled
        default: .constant(true)
        }
    }

    private func controls(in group: SettingsFunctionalGroup) -> some View {
        ForEach(registry.bodyControls(in: group)) { descriptor in
            controlRow(descriptor)
        }
    }

    @ViewBuilder
    private func controlRow(_ descriptor: SettingsControlDescriptor) -> some View {
        switch descriptor.id {
        case .launchAtLogin:
            Toggle("Launch at Login", isOn: $model.launchAtLogin)
                .accessibilityLabel(descriptor.accessibilityLabel)
        case .clipboardOnShortcut:
            Toggle(
                "Translate Clipboard When Opened by Shortcut",
                isOn: $model.translateClipboardOnShortcut
            )
            .padding(.leading, 20)
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
            // 可见文案不再重复 provider 名（二级标题已经写了），但 accessibilityLabel 保留前缀：
            // VoiceOver 会脱离上下文单独朗读某一行。
            SecureField("API Key", text: $model.googleAPIKey)
                .labelsHidden()
                .disabled(!descriptor.isEnabled)
                .accessibilityLabel(descriptor.accessibilityLabel)
        case .googleTest:
            Button("Test Connection") {
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
            TextField("Base URL", text: $model.llmBaseURL)
                .labelsHidden()
                .accessibilityLabel(descriptor.accessibilityLabel)
        case .llmAPIKey:
            SecureField("API Key", text: $model.llmAPIKey)
                .labelsHidden()
                .disabled(!descriptor.isEnabled)
                .accessibilityLabel(descriptor.accessibilityLabel)
        case .llmModel:
            TextField("Model", text: $model.llmModel)
                .labelsHidden()
                .accessibilityLabel(descriptor.accessibilityLabel)
        case .llmTest:
            Button("Test Connection") {
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
        case .saveStatus, .save, .googleEnabled, .llmEnabled:
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
