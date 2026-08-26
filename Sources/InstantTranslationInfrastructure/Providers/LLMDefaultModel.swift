import Foundation

/// Base URL 指向 OpenRouter 而用户没填模型时的兜底模型。
///
/// 兜底值刻意不写进偏好：留空的语义是「跟随默认」，slug 以后变了发个版本就能
/// 把所有人修好；一旦写进磁盘，失效的名字会一直留在那里，而用户并不知道
/// 那是自动填进去的。
public enum LLMDefaultModel {
    /// OpenRouter 的 Free Models Router：从当前免费模型里随机挑一个来应答。
    public static let openRouterFreeRouter = "openrouter/free"

    /// 返回 nil 表示该端点没有兜底，模型仍然必须由用户提供。
    public static func resolve(baseURL: String) -> String? {
        switch ProviderBrandResolver.resolve(baseURL: baseURL) {
        case .openRouter:
            openRouterFreeRouter
        case .googleTranslate, .openAI, .deepSeek, .genericAI:
            nil
        }
    }
}
