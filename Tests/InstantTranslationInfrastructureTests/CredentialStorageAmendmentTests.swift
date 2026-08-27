import Foundation
import Security
import XCTest
@testable import InstantTranslationInfrastructure

final class CredentialStorageAmendmentTests: XCTestCase {
    func testEveryOperationUsesTheSingleFileBasedV3Namespace() throws {
        let client = RecordingSecItemClient()
        let store = KeychainCredentialStore(client: client)

        try store.write("value", for: .googleAPIKey)
        _ = try store.read(.googleAPIKey)
        try store.delete(.googleAPIKey)

        XCTAssertFalse(client.queries.isEmpty)
        for query in client.queries {
            XCTAssertEqual(
                query[kSecAttrService as String] as? String,
                "com.instanttranslation.macos.credentials.v3"
            )
            XCTAssertEqual(query[kSecAttrAccount as String] as? String, "google-api-key")
            XCTAssertNil(query[kSecUseDataProtectionKeychain as String])
            XCTAssertNil(query[kSecAttrAccessGroup as String])
            XCTAssertNil(query[kSecAttrAccessible as String])
        }
    }

    func testCustomServiceDoesNotAddDataProtectionOnlyAttributes() throws {
        let client = RecordingSecItemClient()
        let store = KeychainCredentialStore(service: "test.service", client: client)

        try store.write("value", for: .llmAPIKey)

        let query = try XCTUnwrap(client.queries.first)
        XCTAssertEqual(query[kSecAttrService as String] as? String, "test.service")
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "llm-api-key")
        XCTAssertNil(query[kSecUseDataProtectionKeychain as String])
        XCTAssertNil(query[kSecAttrAccessGroup as String])
        XCTAssertNil(query[kSecAttrAccessible as String])
    }

    func testReadFailureIsReturnedWithoutRetryingAnotherKeychain() {
        let client = RecordingSecItemClient(copyStatus: errSecAuthFailed)
        let store = KeychainCredentialStore(client: client)

        XCTAssertThrowsError(try store.read(.googleAPIKey)) { error in
            XCTAssertEqual(error as? KeychainError, .status(errSecAuthFailed))
        }
        XCTAssertEqual(client.queries.count, 1)
        XCTAssertNil(client.queries[0][kSecUseDataProtectionKeychain as String])
    }
}

private final class RecordingSecItemClient: KeychainSecItemClient, @unchecked Sendable {
    private let copyStatus: OSStatus
    private(set) var queries: [[String: Any]] = []
    private(set) var addedAttributes: [[String: Any]] = []
    private var item: [String: Any]?

    init(copyStatus: OSStatus = errSecSuccess) {
        self.copyStatus = copyStatus
    }

    func copyMatching(_ query: [String: Any]) -> KeychainSecItemResult {
        queries.append(query)
        guard copyStatus == errSecSuccess else {
            return KeychainSecItemResult(status: copyStatus, item: nil)
        }
        guard let item else {
            return KeychainSecItemResult(status: errSecItemNotFound, item: nil)
        }
        return KeychainSecItemResult(
            status: errSecSuccess,
            item: item[kSecValueData as String]
        )
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        queries.append(query)
        guard item != nil else { return errSecItemNotFound }
        attributes.forEach { item?[$0.key] = $0.value }
        return errSecSuccess
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        queries.append(attributes)
        addedAttributes.append(attributes)
        item = attributes
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        queries.append(query)
        item = nil
        return errSecSuccess
    }
}
