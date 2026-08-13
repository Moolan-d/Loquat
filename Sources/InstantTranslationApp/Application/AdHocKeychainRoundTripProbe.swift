import Foundation
import InstantTranslationInfrastructure

public enum AdHocKeychainRoundTripProbeError: Error, Equatable, Sendable {
    case invalidIdentifiers
    case roundTripFailed
    case cleanupFailed
}

public enum AdHocKeychainRoundTripProbe {
    public static func run(service: String, account: String) throws {
        try run(service: service, account: account) { service, backend in
            KeychainCredentialStore(service: service, backend: backend)
        }
    }

    static func run(
        service: String,
        account: String,
        makeStore: (String, KeychainBackend) -> any CredentialStoring
    ) throws {
        guard service.hasPrefix("com.instanttranslation.macos.credentials.probe."),
              account.hasPrefix("probe."),
              service.count > "com.instanttranslation.macos.credentials.probe.".count,
              account.count > "probe.".count
        else {
            throw AdHocKeychainRoundTripProbeError.invalidIdentifiers
        }

        let store = makeStore(service, .fileBased)
        let key = CredentialKey.custom(account)
        let generatedValue = UUID().uuidString

        do {
            try store.write(generatedValue, for: key)
            guard try store.read(key) == generatedValue else {
                throw AdHocKeychainRoundTripProbeError.roundTripFailed
            }
        } catch {
            // probe 值只存在于专用 service/account；失败路径也尽力清理，且不打印值或底层错误。
            try? store.delete(key)
            throw AdHocKeychainRoundTripProbeError.roundTripFailed
        }

        do {
            try store.delete(key)
        } catch {
            throw AdHocKeychainRoundTripProbeError.cleanupFailed
        }
    }
}
