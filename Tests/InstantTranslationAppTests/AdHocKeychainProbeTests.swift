import XCTest
import InstantTranslationInfrastructure
@testable import InstantTranslationApp

final class AdHocKeychainProbeTests: XCTestCase {
    func testProbeUsesExplicitFileBasedStoreAndCleansGeneratedValue() throws {
        let store = ProbeCredentialStore()
        var capturedService: String?
        var capturedBackend: KeychainBackend?

        try AdHocKeychainRoundTripProbe.run(
            service: "com.instanttranslation.macos.credentials.probe.tests",
            account: "probe.round-trip",
            makeStore: { service, backend in
                capturedService = service
                capturedBackend = backend
                return store
            }
        )

        XCTAssertEqual(
            capturedService,
            "com.instanttranslation.macos.credentials.probe.tests"
        )
        XCTAssertEqual(capturedBackend, .fileBased)
        XCTAssertEqual(store.operations.map(\.name), ["write", "read", "delete"])
        XCTAssertNil(store.value)
        XCTAssertEqual(store.operations.map(\.key), [.custom("probe.round-trip"), .custom("probe.round-trip"), .custom("probe.round-trip")])
    }

    func testProbeRejectsProductionOrEmptyIdentifiersBeforeOpeningKeychain() {
        var factoryCallCount = 0
        let makeStore: (String, KeychainBackend) -> any CredentialStoring = { _, _ in
            factoryCallCount += 1
            return ProbeCredentialStore()
        }

        XCTAssertThrowsError(
            try AdHocKeychainRoundTripProbe.run(
                service: "com.instanttranslation.macos.credentials",
                account: "google-api-key",
                makeStore: makeStore
            )
        ) { error in
            XCTAssertEqual(error as? AdHocKeychainRoundTripProbeError, .invalidIdentifiers)
        }
        XCTAssertEqual(factoryCallCount, 0)
    }
}

private final class ProbeCredentialStore: CredentialStoring, @unchecked Sendable {
    struct Operation {
        let name: String
        let key: CredentialKey
    }

    var operations: [Operation] = []
    var value: String?

    func read(_ key: CredentialKey) throws -> String? {
        operations.append(Operation(name: "read", key: key))
        return value
    }

    func write(_ value: String, for key: CredentialKey) throws {
        operations.append(Operation(name: "write", key: key))
        self.value = value
    }

    func delete(_ key: CredentialKey) throws {
        operations.append(Operation(name: "delete", key: key))
        value = nil
    }
}
