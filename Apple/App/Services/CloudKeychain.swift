import Foundation
import Security

/// Where synced items live
protocol CloudItemStoring {
    func all() -> [String: Data]
    func set(_ data: Data, for account: String) throws
    func delete(_ account: String)
}

/// Keychain items iCloud Keychain carries to the user's other devices
struct CloudKeychain: CloudItemStoring {
    private let service = "com.skaymer.gryonixnexus.cloudsync"

    private var base: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    func all() -> [String: Data] {
        var query = base
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [:] }
        var found: [String: Data] = [:]
        for item in items {
            if let account = item[kSecAttrAccount as String] as? String,
               let data = item[kSecValueData as String] as? Data {
                found[account] = data
            }
        }
        return found
    }

    func set(_ data: Data, for account: String) throws {
        var match = base
        match[kSecAttrAccount as String] = account
        let status = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainStore.KeychainError.unexpectedStatus(status) }
        var item = match
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainStore.KeychainError.unexpectedStatus(added) }
    }

    func delete(_ account: String) {
        var match = base
        match[kSecAttrAccount as String] = account
        SecItemDelete(match as CFDictionary)
    }
}

/// The same contract kept in memory, for tests
final class MemoryCloudItems: CloudItemStoring {
    private(set) var items: [String: Data] = [:]

    func all() -> [String: Data] { items }
    func set(_ data: Data, for account: String) throws { items[account] = data }
    func delete(_ account: String) { items[account] = nil }
}
