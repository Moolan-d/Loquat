import Foundation
import Security

public enum CredentialKey: Hashable, Sendable {
    case googleAPIKey
    case llmAPIKey
    case custom(String)

    var account: String {
        switch self {
        case .googleAPIKey:
            "google-api-key"
        case .llmAPIKey:
            "llm-api-key"
        case .custom(let value):
            value
        }
    }
}

public protocol CredentialStoring: Sendable {
    func read(_ key: CredentialKey) throws -> String?
    func write(_ value: String, for key: CredentialKey) throws
    func delete(_ key: CredentialKey) throws
}

public final class KeychainCredentialStore: CredentialStoring, @unchecked Sendable {
    private let service: String

    public init(service: String = "com.instanttranslation.macos.credentials") {
        self.service = service
    }

    public func read(_ key: CredentialKey) throws -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.status(status)
        }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ value: String, for key: CredentialKey) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            // 仅在设备解锁时可访问，且不迁移到其他设备，降低 API 密钥暴露面。
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(baseQuery(key) as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.status(updateStatus)
        }

        var item = baseQuery(key)
        attributes.forEach { item[$0.key] = $0.value }
        // 先 update、仅在不存在时 add，避免预检与写入之间出现竞态。
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.status(addStatus)
        }
    }

    public func delete(_ key: CredentialKey) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    private func baseQuery(_ key: CredentialKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.account,
        ]
    }
}

public enum KeychainError: Error, Equatable, Sendable {
    case status(OSStatus)
}
