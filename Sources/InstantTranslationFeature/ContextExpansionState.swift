import InstantTranslationCore

/// 「更多语境」这个按需入口的全部状态。刻意不并进 ProviderCardState：
/// 那是首译成败的模型，而补充语境失败时首译仍然成立、卡片照常显示译文，
/// 两者共用一个枚举就会让「译文还在但补充失败」无处表达。
///
/// 各 case 不带 requestID：每一轮新查询都会把它打回 unavailable，
/// 因此非 unavailable 的状态必然属于当前请求；迟到结果由 TranslationSession
/// 持有的任务取消与 requestID 复核挡下，而不是靠状态自己携带身份。
public enum ContextExpansionState: Equatable, Sendable {
    /// 没有可补充的语境：整句翻译、LLM 未启用，或首译尚未成功。入口不渲染。
    case unavailable
    /// 首译已成功且值得追问，等待用户点击。
    case available
    case loading
    case success(ContextExpansionResult)
    case failure
}
