import Foundation
@testable import InstantTranslationInfrastructure

actor StubHTTPTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    let response: HTTPResponse

    init(statusCode: Int, body: String) {
        response = HTTPResponse(data: Data(body.utf8), statusCode: statusCode)
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        return response
    }
}
