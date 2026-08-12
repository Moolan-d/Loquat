import Foundation
import XCTest
@testable import InstantTranslationInfrastructure

final class NetworkingSecurityTests: XCTestCase {
    func testEphemeralConfigurationHasNoPersistentStores() {
        let configuration = URLSessionHTTPTransport.makeConfiguration()

        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testEndpointPolicyAllowsHTTPSAndLoopbackHTTPOnly() throws {
        XCTAssertNoThrow(try EndpointPolicy.validatedAPIBaseURL("https://api.openai.com/v1"))
        XCTAssertNoThrow(try EndpointPolicy.validatedAPIBaseURL("http://127.0.0.1:11434/v1"))
        XCTAssertNoThrow(try EndpointPolicy.validatedAPIBaseURL("http://[::1]:1234/v1"))
        XCTAssertThrowsError(try EndpointPolicy.validatedAPIBaseURL("http://example.com/v1"))
        XCTAssertThrowsError(try EndpointPolicy.validatedAPIBaseURL("https://user:pass@example.com/v1?key=secret"))
    }

    func testDiagnosticEventCannotContainRequestTextOrCredentials() {
        let event = TranslationLogEvent(
            providerID: .llm,
            requestID: UUID(),
            statusCode: 429,
            durationMilliseconds: 80
        )

        let description = event.description
        XCTAssertFalse(description.contains("Authorization"))
        XCTAssertFalse(description.contains("translation text"))
    }

    func testProviderErrorMapperCoversAuthenticationRateNetworkTimeoutAndCancellation() {
        XCTAssertEqual(ProviderErrorMapper.map(statusCode: 403), .invalidCredentials)
        XCTAssertEqual(ProviderErrorMapper.map(statusCode: 429), .rateLimited)
        XCTAssertEqual(ProviderErrorMapper.map(URLError(.notConnectedToInternet)), .networkUnavailable)
        XCTAssertEqual(ProviderErrorMapper.map(URLError(.timedOut)), .timedOut)
        XCTAssertEqual(ProviderErrorMapper.map(CancellationError()), .cancelled)
    }
}
