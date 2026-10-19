import Foundation
import Security
import VPNTunnel

/// A tunnel's configuration text, in the Keychain
struct KeychainTunnelSecretStore: TunnelSecretStoring {
    private let service = "com.skaymer.gryonixnexus.tunnel"

    func secret(for account: String) -> String? {
        #if DEBUG
        if MemoryKeychain.isArmed {
            return MemoryKeychain.shared.data(service: service, account: account)
                .flatMap { String(data: $0, encoding: .utf8) }
        }
        #endif
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func store(_ secret: String, for account: String) throws {
        let data = Data(secret.utf8)
        #if DEBUG
        if MemoryKeychain.isArmed {
            MemoryKeychain.shared.set(data, service: service, account: account)
            return
        }
        #endif
        var attributes = baseQuery(account: account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update = [kSecValueData as String: data] as CFDictionary
            let updateStatus = SecItemUpdate(baseQuery(account: account) as CFDictionary, update)
            guard updateStatus == errSecSuccess else {
                throw KeychainStore.KeychainError.unexpectedStatus(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainStore.KeychainError.unexpectedStatus(status)
        }
    }

    func delete(_ account: String) {
        #if DEBUG
        if MemoryKeychain.isArmed {
            MemoryKeychain.shared.delete(service: service, account: account)
            return
        }
        #endif
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
