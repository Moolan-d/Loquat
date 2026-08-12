public struct SpeechRequest: Hashable, Sendable {
    public let text: String
    public let language: LanguageID
    public let voiceID: String?
    public let rate: Double
    public let pitch: Double

    public init(text: String, language: LanguageID, voiceID: String?, rate: Double, pitch: Double) {
        self.text = text
        self.language = language
        self.voiceID = voiceID
        self.rate = rate
        self.pitch = pitch
    }
}

public protocol SpeechProvider: Sendable {
    func speak(_ request: SpeechRequest) async throws
    func stop() async
}
