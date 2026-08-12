/// 仅授予等待完成的能力；底层重试任务的取消权始终保留在会话中。
public struct TranslationRetryCompletion: Sendable {
    private let task: Task<Void, Never>

    init(task: Task<Void, Never>) {
        self.task = task
    }

    public func wait() async {
        await task.value
    }
}
