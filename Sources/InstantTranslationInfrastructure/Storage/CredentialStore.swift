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

public enum KeychainBackend: Equatable, Sendable {
    case fileBased
    case dataProtection(accessGroup: String)
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
    private let backend: KeychainBackend
    private let client: any KeychainSecItemClient

    public init(
        service: String = "com.instanttranslation.macos.credentials",
        backend: KeychainBackend
    ) {
        self.service = service
        self.backend = backend
        client = SystemKeychainSecItemClient()
    }

    init(
        service: String,
        backend: KeychainBackend,
        client: any KeychainSecItemClient
    ) {
        self.service = service
        self.backend = backend
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
            // 仅在设备解锁时可访问，且不迁移到其他设备，降低 API 密钥暴露面。
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
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
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.account,
        ]
        switch backend {
        case .fileBased:
            // ad-hoc 宿主没有团队 access group；文件型查询必须省略两项，不能伪造 entitlement。
            break
        case .dataProtection(let accessGroup):
            // 已签名宿主只访问构造时验证过的团队组，禁止遇错后降级到文件型 Keychain。
            query[kSecUseDataProtectionKeychain as String] = true
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

public enum KeychainError: Error, Equatable, Sendable {
    case invalidData
    case status(OSStatus)
}

public struct CredentialMigrationError: Error, Equatable, Sendable {
    public enum Stage: Equatable, Sendable {
        case destinationRead
        case sourceRead
        case destinationWrite
        case verificationRead
        case verificationMismatch
        case sourceDelete
    }

    public let key: CredentialKey
    public let stage: Stage

    public init(key: CredentialKey, stage: Stage) {
        self.key = key
        self.stage = stage
    }
}

public struct CredentialMigrator: Sendable {
    private let source: any CredentialStoring
    private let destination: any CredentialStoring

    public init(
        source: any CredentialStoring,
        destination: any CredentialStoring
    ) {
        self.source = source
        self.destination = destination
    }

    public func migrate() throws {
        try migrate(keys: [.googleAPIKey, .llmAPIKey])
    }

    func migrate(keys: [CredentialKey]) throws {
        for key in keys {
            try migrate(key)
        }
    }

    private func migrate(_ key: CredentialKey) throws {
        let existingDestination: String?
        do {
            existingDestination = try destination.read(key)
        } catch {
            throw CredentialMigrationError(key: key, stage: .destinationRead)
        }
        guard existingDestination == nil else { return }

        let sourceValue: String?
        do {
            sourceValue = try source.read(key)
        } catch {
            throw CredentialMigrationError(key: key, stage: .sourceRead)
        }
        guard let sourceValue else { return }

        do {
            try destination.write(sourceValue, for: key)
        } catch {
            throw CredentialMigrationError(key: key, stage: .destinationWrite)
        }

        let verifiedValue: String?
        do {
            verifiedValue = try destination.read(key)
        } catch {
            throw CredentialMigrationError(key: key, stage: .verificationRead)
        }
        // 只有逐字节等价的回读通过后才删源；此前任一失败都保留唯一可信副本。
        guard verifiedValue == sourceValue else {
            throw CredentialMigrationError(key: key, stage: .verificationMismatch)
        }

        do {
            try source.delete(key)
        } catch {
            // 此时目标已经验证有效；保留目标并上抛，下一次执行由“目标优先”保证幂等。
            throw CredentialMigrationError(key: key, stage: .sourceDelete)
        }
    }
}
