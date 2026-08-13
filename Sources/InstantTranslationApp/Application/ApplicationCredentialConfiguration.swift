import Foundation
import InstantTranslationInfrastructure

public struct ApplicationCredentialConfiguration: Equatable, Sendable {
    public let backend: KeychainBackend
    public let migrationSourceBackend: KeychainBackend?

    public init(
        backend: KeychainBackend,
        migrationSourceBackend: KeychainBackend? = nil
    ) {
        self.backend = backend
        self.migrationSourceBackend = migrationSourceBackend
    }

    static func resolve(bundle: Bundle = .main) throws -> Self {
        try resolve(
            infoDictionary: bundle.infoDictionary ?? [:],
            isPackagedApplication: bundle.bundleURL.pathExtension == "app"
        )
    }

    static func resolve(
        infoDictionary: [String: Any],
        isPackagedApplication: Bool
    ) throws -> Self {
        guard let mode = infoDictionary["InstantTranslationSigningMode"] as? String else {
            // SwiftPM 的未打包进程可显式注入配置；只有开发宿主允许缺少 bundle 元数据。
            guard !isPackagedApplication else {
                throw ApplicationCredentialConfigurationError.invalidSigningMetadata
            }
            return Self(backend: .fileBased)
        }

        switch mode {
        case "adhoc":
            return Self(backend: .fileBased)
        case "signed":
            guard let group = infoDictionary["InstantTranslationKeychainAccessGroup"] as? String,
                  isVerifiedApplicationAccessGroup(group)
            else {
                throw ApplicationCredentialConfigurationError.invalidSigningMetadata
            }
            return Self(
                backend: .dataProtection(accessGroup: group),
                migrationSourceBackend: .fileBased
            )
        default:
            // 已打包应用遇到未知值必须终止凭据初始化，不能静默降级到另一 backend。
            throw ApplicationCredentialConfigurationError.invalidSigningMetadata
        }
    }

    private static func isVerifiedApplicationAccessGroup(_ value: String) -> Bool {
        let suffix = ".com.instanttranslation.macos"
        guard value.hasSuffix(suffix) else { return false }
        let team = String(value.dropLast(suffix.count))
        return !team.isEmpty && team.allSatisfy { character in
            character.isASCII && (character.isUppercase || character.isNumber)
        }
    }
}

public enum ApplicationCredentialConfigurationError: Error, Equatable, Sendable {
    case invalidSigningMetadata
}
