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

struct KeychainSecItemResult {
    let status: OSStatus
    let item: Any?
}

protocol KeychainSecItemClient {
    func copyMatching(_ query: [String: Any]) -> KeychainSecItemResult
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func add(_ attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

private struct SystemKeychainSecItemClient: KeychainSecItemClient {
    func copyMatching(_ query: [String: Any]) -> KeychainSecItemResult {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return KeychainSecItemResult(status: status, item: item)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

public final class KeychainCredentialStore: CredentialStoring, @unchecked Sendable {
    private let service: String
    private let client: any KeychainSecItemClient

    public init(
        service: String = "com.instanttranslation.macos.credentials.v3"
    ) {
        self.service = service
        client = SystemKeychainSecItemClient()
    }

    init(
        service: String = "com.instanttranslation.macos.credentials.v3",
        client: any KeychainSecItemClient
    ) {
        self.service = service
        self.client = client
    }

    public func read(_ key: CredentialKey) throws -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let result = client.copyMatching(query)
        if result.status == errSecItemNotFound {
            return nil
        }
        guard result.status == errSecSuccess else {
            throw KeychainError.status(result.status)
        }
        guard let data = result.item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            throw KeychainError.invalidData
        }
        return value
    }

    public func write(_ value: String, for key: CredentialKey) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
        ]
        let query = baseQuery(key)
        let updateStatus = client.update(query, attributes: attributes)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.status(updateStatus)
        }

        var item = baseQuery(key)
        attributes.forEach { item[$0.key] = $0.value }
        let addStatus = client.add(item)
        if addStatus == errSecSuccess {
            return
        }
        if addStatus == errSecDuplicateItem {
            // 以 Keychain 单次原子操作为并发边界；若另一写入者抢先 add，则重试 update。
            let retryStatus = client.update(query, attributes: attributes)
            guard retryStatus == errSecSuccess else {
                throw KeychainError.status(retryStatus)
            }
            return
        }
        throw KeychainError.status(addStatus)
    }

    public func delete(_ key: CredentialKey) throws {
        let status = client.delete(baseQuery(key))
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
    case invalidData
    case status(OSStatus)
}
