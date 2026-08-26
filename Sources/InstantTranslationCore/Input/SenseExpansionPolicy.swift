import Foundation

/// 判定这次输入是「查词」还是「翻译一句话」。
///
/// 只有查词才值得让模型附带俚语、网络热词与固定搭配：查 beef 想知道它还能指「过节」，
/// 而翻译一整句时这些条目只会挤占卡片，也让请求平白变慢。判据取输入长度——
/// 它不需要额外一轮模型调用，代价为零，代价为零才配放在每次请求的必经之路上。
///
/// 已知的漏网之鱼：长句里夹着俚语时不会展开。这是刻意让步，
/// 换取「短输入必展开」这条用户能自己预测的规则。
public struct SenseExpansionPolicy: Sendable {
    public let maximumWordCount: Int
    public let maximumCharacterCount: Int

    public init(maximumWordCount: Int = 3, maximumCharacterCount: Int = 6) {
        self.maximumWordCount = maximumWordCount
        self.maximumCharacterCount = maximumCharacterCount
    }

    public func shouldExpand(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // 中文不靠空格分词，按词数整段永远只算一个词，闸门会全线失守；
        // 只要含汉字就改数字数，中英混排（"内卷 subculture"）也一并落到这条规则上。
        if HanScript.contains(trimmed) {
            return trimmed.filter { !$0.isWhitespace }.count <= maximumCharacterCount
        }
        return trimmed.split(whereSeparator: { $0.isWhitespace }).count <= maximumWordCount
    }
}
