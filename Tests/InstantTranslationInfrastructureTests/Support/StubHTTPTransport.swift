import Foundation
@testable import InstantTranslationInfrastructure

actor StubHTTPTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    private let outcome: @Sendable () throws -> HTTPResponse

    init(statusCode: Int, body: String) {
        let response = HTTPResponse(data: Data(body.utf8), statusCode: statusCode)
        outcome = { response }
    }

    /// 按顺序应答的构造：一次会话里可能连着发两次请求（首译，随后按需语境），
    /// 每次得拿到不同的 body 才测得出第二次问了什么。
    init(responses: [HTTPResponse]) {
        let queued = QueuedResponses(responses)
        outcome = { try queued.next() }
    }

    init<Failure: Error & Sendable>(error: Failure) {
        outcome = { throw error }
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        return try outcome()
    }
}

extension HTTPResponse {
    init(statusCode: Int, body: String) {
        self.init(data: Data(body.utf8), statusCode: statusCode)
    }
}

/// outcome 是 @Sendable 闭包，不能捕获可变数组；用一个带锁的小盒子推进队列。
private final class QueuedResponses: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: [HTTPResponse]

    init(_ responses: [HTTPResponse]) {
        remaining = responses
    }

    func next() throws -> HTTPResponse {
        lock.lock()
        defer { lock.unlock() }
        guard !remaining.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return remaining.removeFirst()
    }
}
