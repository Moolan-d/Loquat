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
        "provider=\(diagnosticProvider) request=\(requestID.uuidString) status=\(statusCode.map(String.init) ?? "none") durationMs=\(durationMilliseconds)"
    }

    private var diagnosticProvider: String {
        switch providerID {
        case .google:
            "google"
        case .llm:
            "llm"
        default:
            "unknown"
        }
    }
}

public struct TranslationLogger: Sendable {
    private let logger = Logger(subsystem: "com.instanttranslation.macos", category: "translation")

    public init() {}

    public func record(_ event: TranslationLogEvent) {
        // 日志只接收固定的匿名元数据事件，未知 ProviderID 也映射为常量，绝不把原文或密钥写入日志。
        logger.info("\(event.description, privacy: .public)")
    }
}
