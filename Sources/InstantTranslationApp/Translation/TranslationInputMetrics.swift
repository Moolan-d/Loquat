import CoreGraphics

/// 输入框高度策略：随内容增高，到 `maximumLines` 行封顶后改由内部滚动承担。
/// 弹窗宽度固定，长文本若继续撑高会挤掉下方提示与结果卡片，因此这里必须夹紧。
struct TranslationInputMetrics: Equatable {
    static let maximumLines = 3

    let lineHeight: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat

    var minimumHeight: CGFloat { lineHeight + topInset + bottomInset }

    /// 封顶高度不含下边距：可见区就是文档坐标的 0..maximumHeight，而那段留白紧挨着
    /// 第四行，留着只会把下一行的顶端露出来。再向下取整到整点，否则 SwiftUI 的像素
    /// 对齐会把外框上调半点，又漏出一截。
    var maximumHeight: CGFloat {
        (topInset + lineHeight * CGFloat(Self.maximumLines)).rounded(.down)
    }

    /// 一律夹在上下界之间：正好三行与超过三行落在同一高度，
    /// 输入框不会在内容越过封顶的那一刻反而变矮。
    func height(forMeasuredTextHeight measured: CGFloat) -> CGFloat {
        min(max(measured + topInset + bottomInset, minimumHeight), maximumHeight)
    }
}
