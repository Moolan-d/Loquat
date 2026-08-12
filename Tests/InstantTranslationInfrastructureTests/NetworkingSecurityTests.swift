import Foundation
import InstantTranslationCore
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

    func testEndpointPolicyPreservesEncodedPathDelimitersWhenNormalizingTrailingSlashes() throws {
        let url = try EndpointPolicy.validatedAPIBaseURL("https://api.openai.com/v1%2Fmodels%2e%2e/")

        XCTAssertEqual(url.absoluteString, "https://api.openai.com/v1%2Fmodels%2e%2e")
    }

    func testTransportRejectsInsecureInitialRequestAndRedirectTarget() async {
        let insecureRequest = URLRequest(url: URL(string: "http://example.com/v1")!)
        let secureRequest = URLRequest(url: URL(string: "https://api.openai.com/v1")!)
        let transport = URLSessionHTTPTransport()

        do {
            _ = try await transport.send(insecureRequest)
            XCTFail("Remote HTTP requests must be rejected before sending")
        } catch let error as TranslationProviderError {
            XCTAssertEqual(error, .insecureEndpoint)
        } catch {
            XCTFail("Expected insecureEndpoint, received \(error)")
        }

        XCTAssertFalse(URLSessionHTTPTransport.shouldFollowRedirect(to: insecureRequest))
        XCTAssertTrue(URLSessionHTTPTransport.shouldFollowRedirect(to: secureRequest))
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

    func testDiagnosticEventRedactsCustomProviderRawValue() {
        let event = TranslationLogEvent(
            providerID: ProviderID(rawValue: "Authorization: Bearer secret translation text"),
            requestID: UUID(),
            statusCode: nil,
            durationMilliseconds: 80
        )

        XCTAssertTrue(event.description.contains("provider=unknown"))
        XCTAssertFalse(event.description.contains("Authorization"))
        XCTAssertFalse(event.description.contains("secret"))
        XCTAssertFalse(event.description.contains("translation text"))
    }

    func testProviderErrorMapperCoversAuthenticationRateNetworkTimeoutAndCancellation() {
        XCTAssertEqual(ProviderErrorMapper.map(statusCode: 403), .invalidCredentials)
        XCTAssertEqual(ProviderErrorMapper.map(statusCode: 429), .rateLimited)
        XCTAssertEqual(ProviderErrorMapper.map(URLError(.notConnectedToInternet)), .networkUnavailable)
        XCTAssertEqual(ProviderErrorMapper.map(URLError(.timedOut)), .timedOut)
        XCTAssertEqual(ProviderErrorMapper.map(CancellationError()), .cancelled)
    }
}
