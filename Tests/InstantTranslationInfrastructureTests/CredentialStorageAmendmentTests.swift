import Foundation
import Security
import XCTest
@testable import InstantTranslationInfrastructure

final class CredentialStorageAmendmentTests: XCTestCase {
    private let service = "com.instanttranslation.macos.credentials"
    private let accessGroup = "TEAM123.com.instanttranslation.macos"

    func testFileBasedBackendOmitsDataProtectionAndAccessGroupFromEveryQuery() throws {
        let client = RecordingSecItemClient()
        let store = KeychainCredentialStore(
            service: service,
            backend: .fileBased,
            client: client
        )

        try store.write("value", for: .googleAPIKey)
        _ = try store.read(.googleAPIKey)
        try store.delete(.googleAPIKey)

        XCTAssertFalse(client.queries.isEmpty)
        for query in client.queries {
            XCTAssertNil(query[kSecUseDataProtectionKeychain as String])
            XCTAssertNil(query[kSecAttrAccessGroup as String])
            XCTAssertEqual(query[kSecAttrService as String] as? String, service)
            XCTAssertEqual(query[kSecAttrAccount as String] as? String, "google-api-key")
        }
        XCTAssertEqual(
            client.addedAttributes.first?[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
    }

    func testDataProtectionBackendAddsTrueAndExactAccessGroupToEveryQuery() throws {
        let client = RecordingSecItemClient()
        let store = KeychainCredentialStore(
            service: service,
            backend: .dataProtection(accessGroup: accessGroup),
            client: client
        )

        try store.write("value", for: .llmAPIKey)
        _ = try store.read(.llmAPIKey)
        try store.delete(.llmAPIKey)

        XCTAssertFalse(client.queries.isEmpty)
        for query in client.queries {
            XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, true)
            XCTAssertEqual(query[kSecAttrAccessGroup as String] as? String, accessGroup)
            XCTAssertEqual(query[kSecAttrService as String] as? String, service)
            XCTAssertEqual(query[kSecAttrAccount as String] as? String, "llm-api-key")
        }
        XCTAssertEqual(
            client.addedAttributes.first?[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
    }

    func testEntitlementFailureDoesNotRetryAgainstFileBasedBackend() {
        let client = RecordingSecItemClient(copyStatus: errSecMissingEntitlement)
        let store = KeychainCredentialStore(
            service: service,
            backend: .dataProtection(accessGroup: accessGroup),
            client: client
        )

        XCTAssertThrowsError(try store.read(.googleAPIKey)) { error in
            XCTAssertEqual(error as? KeychainError, .status(errSecMissingEntitlement))
        }
        XCTAssertEqual(client.queries.count, 1)
        XCTAssertEqual(
            client.queries[0][kSecAttrAccessGroup as String] as? String,
            accessGroup
        )
    }

    func testMigrationWritesVerifiesThenDeletesBothSourceCredentials() throws {
        let operations = OperationRecorder()
        let source = RecordingCredentialStore(
            values: [.googleAPIKey: "google-secret", .llmAPIKey: "llm-secret"],
            role: "source",
            recorder: operations
        )
        let destination = RecordingCredentialStore(
            role: "destination",
            recorder: operations
        )

        try CredentialMigrator(source: source, destination: destination).migrate()

        XCTAssertEqual(destination.values[.googleAPIKey], "google-secret")
        XCTAssertEqual(destination.values[.llmAPIKey], "llm-secret")
        XCTAssertNil(source.values[.googleAPIKey])
        XCTAssertNil(source.values[.llmAPIKey])
        XCTAssertEqual(
            operations.values,
            [
                "destination.read.google-api-key",
                "source.read.google-api-key",
                "destination.write.google-api-key",
                "destination.read.google-api-key",
                "source.delete.google-api-key",
                "destination.read.llm-api-key",
                "source.read.llm-api-key",
                "destination.write.llm-api-key",
                "destination.read.llm-api-key",
                "source.delete.llm-api-key",
            ]
        )
    }

    func testMigrationDestinationWinsWithoutReadingOrDeletingSource() throws {
        let operations = OperationRecorder()
        let source = RecordingCredentialStore(
            values: [.googleAPIKey: "source-secret"],
            role: "source",
            recorder: operations
        )
        let destination = RecordingCredentialStore(
            values: [.googleAPIKey: "destination-secret"],
            role: "destination",
            recorder: operations
        )

        try CredentialMigrator(source: source, destination: destination)
            .migrate(keys: [.googleAPIKey])

        XCTAssertEqual(destination.values[.googleAPIKey], "destination-secret")
        XCTAssertEqual(source.values[.googleAPIKey], "source-secret")
        XCTAssertEqual(operations.values, ["destination.read.google-api-key"])
    }

    func testMigrationWriteFailureIsSanitizedAndLeavesSourceIntact() {
        let operations = OperationRecorder()
        let source = RecordingCredentialStore(
            values: [.googleAPIKey: "source-secret"],
            role: "source",
            recorder: operations
        )
        let destination = RecordingCredentialStore(
            role: "destination",
            recorder: operations,
            failures: [.write: TestFailure.containsSensitiveText("source-secret")]
        )

        XCTAssertThrowsError(
            try CredentialMigrator(source: source, destination: destination)
                .migrate(keys: [.googleAPIKey])
        ) { error in
            XCTAssertEqual(
                error as? CredentialMigrationError,
                CredentialMigrationError(key: .googleAPIKey, stage: .destinationWrite)
            )
            XCTAssertFalse(String(describing: error).contains("source-secret"))
        }
        XCTAssertEqual(source.values[.googleAPIKey], "source-secret")
        XCTAssertNil(destination.values[.googleAPIKey])
    }

    func testMigrationSourceReadFailureIsSanitizedAndStopsBeforeWrite() {
        let operations = OperationRecorder()
        let source = RecordingCredentialStore(
            role: "source",
            recorder: operations,
            failures: [.read: TestFailure.containsSensitiveText("source-secret")]
        )
        let destination = RecordingCredentialStore(
            role: "destination",
            recorder: operations
        )

        XCTAssertThrowsError(
            try CredentialMigrator(source: source, destination: destination)
                .migrate(keys: [.googleAPIKey])
        ) { error in
            XCTAssertEqual(
                error as? CredentialMigrationError,
                CredentialMigrationError(key: .googleAPIKey, stage: .sourceRead)
            )
            XCTAssertFalse(String(describing: error).contains("source-secret"))
        }
        XCTAssertEqual(
            operations.values,
            ["destination.read.google-api-key", "source.read.google-api-key"]
        )
    }

    func testMigrationDestinationReadFailureIsSanitizedAndNeverReadsSource() {
        let operations = OperationRecorder()
        let source = RecordingCredentialStore(
            values: [.googleAPIKey: "source-secret"],
            role: "source",
            recorder: operations
        )
        let destination = RecordingCredentialStore(
            role: "destination",
            recorder: operations,
            failures: [.read: TestFailure.containsSensitiveText("source-secret")]
        )

        XCTAssertThrowsError(
            try CredentialMigrator(source: source, destination: destination)
                .migrate(keys: [.googleAPIKey])
        ) { error in
            XCTAssertEqual(
                error as? CredentialMigrationError,
                CredentialMigrationError(key: .googleAPIKey, stage: .destinationRead)
            )
            XCTAssertFalse(String(describing: error).contains("source-secret"))
        }
        XCTAssertEqual(operations.values, ["destination.read.google-api-key"])
    }

    func testMigrationVerificationReadFailureLeavesSourceIntact() {
        let operations = OperationRecorder()
        let source = RecordingCredentialStore(
            values: [.googleAPIKey: "source-secret"],
            role: "source",
            recorder: operations
        )
        let destination = RecordingCredentialStore(
            role: "destination",
            recorder: operations,
            failReadOnCall: 2
        )

        XCTAssertThrowsError(
            try CredentialMigrator(source: source, destination: destination)
                .migrate(keys: [.googleAPIKey])
        ) { error in
            XCTAssertEqual(
                error as? CredentialMigrationError,
                CredentialMigrationError(key: .googleAPIKey, stage: .verificationRead)
            )
        }
        XCTAssertEqual(source.values[.googleAPIKey], "source-secret")
        XCTAssertEqual(destination.values[.googleAPIKey], "source-secret")
        XCTAssertFalse(operations.values.contains("source.delete.google-api-key"))
    }

    func testMigrationVerificationMismatchLeavesSourceIntact() {
        let operations = OperationRecorder()
        let source = RecordingCredentialStore(
            values: [.googleAPIKey: "source-secret"],
            role: "source",
            recorder: operations
        )
        let destination = RecordingCredentialStore(
            role: "destination",
            recorder: operations,
            replacementWriteValue: "different-value"
        )

        XCTAssertThrowsError(
            try CredentialMigrator(source: source, destination: destination)
                .migrate(keys: [.googleAPIKey])
        ) { error in
            XCTAssertEqual(
                error as? CredentialMigrationError,
                CredentialMigrationError(key: .googleAPIKey, stage: .verificationMismatch)
            )
        }
        XCTAssertEqual(source.values[.googleAPIKey], "source-secret")
        XCTAssertEqual(destination.values[.googleAPIKey], "different-value")
        XCTAssertFalse(operations.values.contains("source.delete.google-api-key"))
    }

    func testMigrationDeleteFailureKeepsVerifiedDestinationAndRetryIsIdempotent() {
        let operations = OperationRecorder()
        let source = RecordingCredentialStore(
            values: [.googleAPIKey: "source-secret"],
            role: "source",
            recorder: operations,
            failures: [.delete: TestFailure.containsSensitiveText("source-secret")]
        )
        let destination = RecordingCredentialStore(
            role: "destination",
            recorder: operations
        )
        let migrator = CredentialMigrator(source: source, destination: destination)

        XCTAssertThrowsError(try migrator.migrate(keys: [.googleAPIKey])) { error in
            XCTAssertEqual(
                error as? CredentialMigrationError,
                CredentialMigrationError(key: .googleAPIKey, stage: .sourceDelete)
            )
            XCTAssertFalse(String(describing: error).contains("source-secret"))
        }
        XCTAssertEqual(destination.values[.googleAPIKey], "source-secret")
        XCTAssertNoThrow(try migrator.migrate(keys: [.googleAPIKey]))
        XCTAssertEqual(destination.values[.googleAPIKey], "source-secret")
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

private final class OperationRecorder: @unchecked Sendable {
    var values: [String] = []
}

private final class RecordingCredentialStore: CredentialStoring, @unchecked Sendable {
    enum Operation: Hashable {
        case read
        case write
        case delete
    }

    var values: [CredentialKey: String]
    private let role: String
    private let recorder: OperationRecorder
    private let failures: [Operation: Error]
    private let replacementWriteValue: String?
    private let failReadOnCall: Int?
    private var readCallCount = 0

    init(
        values: [CredentialKey: String] = [:],
        role: String,
        recorder: OperationRecorder,
        failures: [Operation: Error] = [:],
        replacementWriteValue: String? = nil,
        failReadOnCall: Int? = nil
    ) {
        self.values = values
        self.role = role
        self.recorder = recorder
        self.failures = failures
        self.replacementWriteValue = replacementWriteValue
        self.failReadOnCall = failReadOnCall
    }

    func read(_ key: CredentialKey) throws -> String? {
        recorder.values.append("\(role).read.\(key.account)")
        readCallCount += 1
        if readCallCount == failReadOnCall {
            throw TestFailure.containsSensitiveText("source-secret")
        }
        if let failure = failures[.read] { throw failure }
        return values[key]
    }

    func write(_ value: String, for key: CredentialKey) throws {
        recorder.values.append("\(role).write.\(key.account)")
        if let failure = failures[.write] { throw failure }
        values[key] = replacementWriteValue ?? value
    }

    func delete(_ key: CredentialKey) throws {
        recorder.values.append("\(role).delete.\(key.account)")
        if let failure = failures[.delete] { throw failure }
        values[key] = nil
    }
}

private enum TestFailure: Error {
    case containsSensitiveText(String)
}
