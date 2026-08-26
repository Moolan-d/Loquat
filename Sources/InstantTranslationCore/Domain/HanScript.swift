/// 「这段文本含汉字吗」的唯一判据。方向判定与义项闸门都要问这个问题，
/// 各写一份迟早漂移成两套码位范围，于是抽在这里共用。
public enum HanScript {
    /// 覆盖 CJK 统一表意文字及扩展 A、兼容表意文字，避免仅依赖常用汉字范围误判。
    public static func contains(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
        }
    }
}
