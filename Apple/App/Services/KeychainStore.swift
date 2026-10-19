import Foundation
import Security

struct KeychainStore {
    enum KeychainError: Error, LocalizedError {
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            if case .unexpectedStatus(let status) = self {
                return "Keychain error (OSStatus \(status))"
            }
            return nil
        }
    }

    private let service: String

    init(service: String = "com.skaymer.gryonixnexus") {
        self.service = service
    }

    func data(for account: String) throws -> Data? {
        #if DEBUG
        if MemoryKeychain.isArmed { return MemoryKeychain.shared.data(service: service, account: account) }
        #endif
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess: return item as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError.unexpectedStatus(status)
        }
    }

    func set(_ data: Data, for account: String) throws {
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
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func delete(_ account: String) throws {
        #if DEBUG
        if MemoryKeychain.isArmed {
            MemoryKeychain.shared.delete(service: service, account: account)
            return
        }
        #endif
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// The accounts of this service that start with `prefix`
    func accounts(withPrefix prefix: String) -> [String] {
        #if DEBUG
        if MemoryKeychain.isArmed { return MemoryKeychain.shared.accounts(service: service, prefix: prefix) }
        #endif
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess,
              let rows = found as? [[String: Any]] else { return [] }
        return rows.compactMap { $0[kSecAttrAccount as String] as? String }.filter { $0.hasPrefix(prefix) }
    }

    func string(for account: String) throws -> String? {
        try data(for: account).flatMap { String(data: $0, encoding: .utf8) }
    }

    func set(_ string: String, for account: String) throws {
        try set(Data(string.utf8), for: account)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

#if DEBUG
final class MemoryKeychain: @unchecked Sendable {
    static let shared = MemoryKeychain()

    static let isArmed =
        ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEBUG_MEMORY_KEYCHAIN"] == "1"

    private let lock = NSLock()
    private var items: [String: Data] = [:]

    private func key(_ service: String, _ account: String) -> String { "\(service)\u{1}\(account)" }

    func data(service: String, account: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return items[key(service, account)]
    }

    func set(_ data: Data, service: String, account: String) {
        lock.lock(); defer { lock.unlock() }
        items[key(service, account)] = data
    }

    func delete(service: String, account: String) {
        lock.lock(); defer { lock.unlock() }
        items[key(service, account)] = nil
    }

    func accounts(service: String, prefix: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        let head = "\(service)\u{1}"
        return items.keys.filter { $0.hasPrefix(head + prefix) }.map { String($0.dropFirst(head.count)) }
    }
}
#endif
