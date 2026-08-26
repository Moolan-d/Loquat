import Foundation
import Observation
import InstantTranslationCore

@MainActor
@Observable
public final class TranslationSession {
    public var input = ""
    public private(set) var activeRequest: TranslationRequest?
    public private(set) var states: [ProviderID: ProviderCardState] = [
        .google: .idle,
        .llm: .idle,
    ]
    public private(set) var requiresManualClipboardConfirmation = false
    public private(set) var contextExpansionState: ContextExpansionState = .unavailable
    public var promptPresetID: PromptPresetID

    /// 用户在设置中隐藏的 provider 不参与请求分发，也不在窗口保留条目状态。
    public var enabledProviderIDs: Set<ProviderID> {
        didSet {
            guard enabledProviderIDs != oldValue else { return }
            for providerID in states.keys where !enabledProviderIDs.contains(providerID) {
                states[providerID] = .idle
            }
            // 补充语境是 LLM 的能力，关掉它，那份结果连同入口一起作废。
            if !enabledProviderIDs.contains(.llm) {
                cancelContextExpansion()
            }
        }
    }

    private let coordinator: TranslationCoordinator
    private let resolver = DirectionResolver()
    private let senseExpansionPolicy = SenseExpansionPolicy()
    private var activeTask: Task<Void, Never>?
    private var retryTasks: [ProviderID: Task<Void, Never>] = [:]
    private var contextExpansionTask: Task<Void, Never>?

    public init(
        coordinator: TranslationCoordinator,
        promptPresetID: PromptPresetID,
        enabledProviderIDs: Set<ProviderID> = [.google, .llm]
    ) {
        self.coordinator = coordinator
        self.promptPresetID = promptPresetID
        self.enabledProviderIDs = enabledProviderIDs
    }

    public func submit(
        rawText: String,
        sourceID: InputSourceID,
        manualDirection: TranslationDirection? = nil
    ) {
        guard let source = SourceText(rawValue: rawText, sourceID: sourceID) else { return }

        cancelTasks()
        input = source.value
        requiresManualClipboardConfirmation = false

        let direction = manualDirection ?? resolver.resolve(source.value)
        let request = TranslationRequest(
            id: UUID(),
            text: source.value,
            inputSource: source.sourceID,
            sourceLanguage: direction.source,
            targetLanguage: direction.target,
            directionOrigin: manualDirection == nil ? .detected : .manual,
            promptPresetID: promptPresetID
        )

        activeRequest = request
        for providerID in states.keys {
            states[providerID] = enabledProviderIDs.contains(providerID)
                ? .loading(requestID: request.id)
                : .idle
        }
        let requestedProviderIDs = enabledProviderIDs
        guard !requestedProviderIDs.isEmpty else { return }
        activeTask = Task { [coordinator] in
            for await event in coordinator.events(
                for: request,
                providerIDs: requestedProviderIDs
            ) {
                // 取消负责尽快停工，requestID 校验再拦截已越过取消点的迟到事件，二者缺一不可。
                guard !Task.isCancelled else { return }
                receive(event)
            }
        }
    }

    public func applyClipboardDecision(_ decision: ClipboardDecision) {
        switch decision {
        case .ignore:
            break
        case .translate(let source):
            guard source.value != input else { return }
            submit(rawText: source.value, sourceID: .clipboard)
        case .requireConfirmation(let source):
            guard source.value != input else { return }
            cancelTasks()
            input = source.value
            activeRequest = nil
            states[.google] = .idle
            states[.llm] = .idle
            requiresManualClipboardConfirmation = true
        }
    }

    public func receive(_ event: ProviderEvent) {
        guard let request = activeRequest else { return }

        switch event {
        case .success(let result) where result.requestID == request.id:
            states[result.providerID] = .success(result)
            // 只有查词才配得上「更多语境」：整句翻译没有额外义项可谈，
            // 入口一旦出现就是一条永远问不出东西的死路。
            if result.providerID == .llm, senseExpansionPolicy.shouldExpand(request.text) {
                contextExpansionState = .available
            }
        case .failure(let providerID, let requestID, let error) where requestID == request.id:
            states[providerID] = .failure(requestID: requestID, error)
        default:
            break
        }
    }

    /// 用户点「更多语境」的入口。首译已成、值得追问、且没有正在飞的请求时才发一次；
    /// 加载中和已成功都直接落进 guard，重复点击既不叠加请求也不重置已拿到的结果。
    @discardableResult
    public func requestMoreContexts() -> TranslationTaskCompletion? {
        guard let request = activeRequest,
              enabledProviderIDs.contains(.llm),
              case .success(let existingResult)? = states[.llm],
              existingResult.requestID == request.id,
              contextExpansionState == .available || contextExpansionState == .failure
        else { return nil }

        contextExpansionTask?.cancel()
        contextExpansionState = .loading
        let task = Task { [coordinator] in
            let outcome = await coordinator.expandContext(
                for: request,
                excluding: existingResult
            )
            // 取消负责尽快停工，requestID 复核再拦下已越过取消点的迟到结果：
            // 那份属于上一轮查询，贴到新一轮的卡片上就是张冠李戴。
            guard !Task.isCancelled, activeRequest?.id == request.id else { return }
            switch outcome {
            case .success(let expansion):
                contextExpansionState = .success(expansion)
            case .failure:
                // 补充语境失败只影响这一块，首译结果原样留在卡片上。
                contextExpansionState = .failure
            }
        }
        contextExpansionTask = task
        return TranslationTaskCompletion(task: task)
    }

    /// 作废当前这份补充语境。凡是「这一轮结束了」的路径都要调用，
    /// 否则上一次查询的义项会挂在新词的卡片下面。
    public func cancelContextExpansion() {
        contextExpansionTask?.cancel()
        contextExpansionTask = nil
        contextExpansionState = .unavailable
    }

    public func swapDirectionAndResubmit() {
        guard let request = activeRequest else {
            guard let source = SourceText(rawValue: input, sourceID: .manual) else { return }
            let detected = resolver.resolve(source.value)
            submit(
                rawText: source.value,
                sourceID: .manual,
                manualDirection: .init(source: detected.target, target: detected.source)
            )
            return
        }

        submit(
            rawText: input,
            sourceID: .manual,
            manualDirection: .init(
                source: request.targetLanguage,
                target: request.sourceLanguage
            )
        )
    }

    @discardableResult
    public func retry(providerID: ProviderID) -> TranslationTaskCompletion? {
        guard let request = activeRequest,
              enabledProviderIDs.contains(providerID)
        else { return nil }

        retryTasks[providerID]?.cancel()
        // 重试首译等于把这张卡片打回未完成，挂在它下面的补充语境先跟着作废，
        // 等新的译文回来再重新开放入口。
        if providerID == .llm {
            cancelContextExpansion()
        }
        states[providerID] = .loading(requestID: request.id)
        let task = Task { [coordinator] in
            let event = await coordinator.retry(providerID: providerID, request: request)
            guard !Task.isCancelled else { return }
            receive(event)
        }
        retryTasks[providerID] = task
        return TranslationTaskCompletion(task: task)
    }

    /// 清空一次会话：输入、结果卡片、进行中的请求一起归零。
    /// 弹窗再次唤起时不该还挂着上一轮的译文。activeRequest 置空后，
    /// 已经越过取消点的迟到事件会被 receive 的 guard 挡下，卡片不会又被点亮。
    public func reset() {
        cancelTasks()
        input = ""
        activeRequest = nil
        requiresManualClipboardConfirmation = false
        for providerID in states.keys {
            states[providerID] = .idle
        }
    }

    /// 仅在新请求或进程停止时取消会话；popover 关闭只隐藏界面，不应调用此方法。
    public func cancelAll() {
        cancelTasks()
    }

    private func cancelTasks() {
        activeTask?.cancel()
        activeTask = nil
        retryTasks.values.forEach { $0.cancel() }
        retryTasks.removeAll(keepingCapacity: true)
        cancelContextExpansion()
    }
}
