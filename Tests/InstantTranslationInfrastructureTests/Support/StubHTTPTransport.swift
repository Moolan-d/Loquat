import Foundation
@testable import InstantTranslationInfrastructure

actor StubHTTPTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    private let outcome: @Sendable () throws -> HTTPResponse

    init(statusCode: Int, body: String) {
        let response = HTTPResponse(data: Data(body.utf8), statusCode: statusCode)
        outcome = { response }
    }

    init<Failure: Error & Sendable>(error: Failure) {
        outcome = { throw error }
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        return try outcome()
    }
}
