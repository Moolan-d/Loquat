/// 会话内部任务的完成句柄。存在的理由只有一个：调用方（主要是测试）要能
/// 确定地等到那次异步工作收尾，而不是靠 sleep 猜一个够长的时间。
public struct TranslationTaskCompletion: Sendable {
    private let task: Task<Void, Never>

    init(task: Task<Void, Never>) {
        self.task = task
    }

    public func wait() async {
        await task.value
    }
}
