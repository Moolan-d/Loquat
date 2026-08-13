import XCTest
import InstantTranslationInfrastructure
@testable import InstantTranslationApp

final class SigningModeConfigurationTests: XCTestCase {
    func testAdHocModeSelectsFileBasedBackendWithoutMigration() throws {
        let configuration = try ApplicationCredentialConfiguration.resolve(
            infoDictionary: ["InstantTranslationSigningMode": "adhoc"],
            isPackagedApplication: true
        )

        XCTAssertEqual(configuration.backend, .fileBased)
        XCTAssertNil(configuration.migrationSourceBackend)
    }

    func testSignedModeSelectsVerifiedGroupAndFileMigrationSource() throws {
        let group = "TEAM123.com.instanttranslation.macos"
        let configuration = try ApplicationCredentialConfiguration.resolve(
            infoDictionary: [
                "InstantTranslationSigningMode": "signed",
                "InstantTranslationKeychainAccessGroup": group,
            ],
            isPackagedApplication: true
        )

        XCTAssertEqual(configuration.backend, .dataProtection(accessGroup: group))
        XCTAssertEqual(configuration.migrationSourceBackend, .fileBased)
    }

    func testPackagedMissingOrUnknownModeFailsClosed() {
        for info in [
            [:],
            ["InstantTranslationSigningMode": "SIGNED"],
            ["InstantTranslationSigningMode": "unknown"],
        ] {
            XCTAssertThrowsError(
                try ApplicationCredentialConfiguration.resolve(
                    infoDictionary: info,
                    isPackagedApplication: true
                )
            ) { error in
                XCTAssertEqual(error as? ApplicationCredentialConfigurationError, .invalidSigningMetadata)
            }
        }
    }

    func testSignedModeRejectsMissingOrUnverifiedAccessGroup() {
        for group in [nil, "", "com.instanttranslation.macos", "team123.com.instanttranslation.macos", "TEAM123.other"] {
            var info: [String: Any] = ["InstantTranslationSigningMode": "signed"]
            info["InstantTranslationKeychainAccessGroup"] = group

            XCTAssertThrowsError(
                try ApplicationCredentialConfiguration.resolve(
                    infoDictionary: info,
                    isPackagedApplication: true
                )
            ) { error in
                XCTAssertEqual(error as? ApplicationCredentialConfigurationError, .invalidSigningMetadata)
            }
        }
    }

    func testUnbundledDevelopmentMayUseExplicitConfiguration() {
        let configuration = ApplicationCredentialConfiguration(backend: .fileBased)

        XCTAssertEqual(configuration.backend, .fileBased)
        XCTAssertNil(configuration.migrationSourceBackend)
    }
}
