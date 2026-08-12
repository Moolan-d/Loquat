import Foundation

public struct SourceText: Hashable, Sendable {
    public let value: String
    public let sourceID: InputSourceID

    public init?(rawValue: String, sourceID: InputSourceID) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        value = normalized
        self.sourceID = sourceID
    }
}

public protocol InputSource: Sendable {
    var id: InputSourceID { get }

    func read() async throws -> SourceText?
}

public struct ManualInputSource: InputSource {
    public let id = InputSourceID.manual
    private let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public func read() async throws -> SourceText? {
        SourceText(rawValue: rawValue, sourceID: id)
    }
}
