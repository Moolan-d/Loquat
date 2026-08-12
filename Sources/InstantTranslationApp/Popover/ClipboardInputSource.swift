import AppKit
import InstantTranslationCore

public struct ClipboardInputSource: InputSource, @unchecked Sendable {
    public let id = InputSourceID.clipboard

    private let readString: @MainActor @Sendable () -> String?

    public init(
        readString: @escaping @MainActor @Sendable () -> String? = {
            NSPasteboard.general.string(forType: .string)
        }
    ) {
        self.readString = readString
    }

    public func read() async throws -> SourceText? {
        // 系统剪贴板只在弹窗即将显示且偏好开启时读取，此类型不轮询也不保存原始内容。
        await MainActor.run {
            guard let value = readString() else { return nil }
            return SourceText(rawValue: value, sourceID: id)
        }
    }
}
