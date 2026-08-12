import Foundation
import InstantTranslationCore
import OSLog

public struct TranslationLogEvent: CustomStringConvertible, Sendable {
    public let providerID: ProviderID
    public let requestID: UUID
    public let statusCode: Int?
    public let durationMilliseconds: Int

    public init(
        providerID: ProviderID,
        requestID: UUID,
        statusCode: Int?,
        durationMilliseconds: Int
    ) {
        self.providerID = providerID
        self.requestID = requestID
        self.statusCode = statusCode
        self.durationMilliseconds = durationMilliseconds
    }

    public var description: String {
        "provider=\(providerID.rawValue) request=\(requestID.uuidString) status=\(statusCode.map(String.init) ?? "none") durationMs=\(durationMilliseconds)"
    }
}

public struct TranslationLogger: Sendable {
    private let logger = Logger(subsystem: "com.instanttranslation.macos", category: "translation")

    public init() {}

    public func record(_ event: TranslationLogEvent) {
        // 日志只接收固定的匿名元数据事件，接口中没有原文或密钥字段，杜绝敏感内容被记录。
        logger.info("\(event.description, privacy: .public)")
    }
}
