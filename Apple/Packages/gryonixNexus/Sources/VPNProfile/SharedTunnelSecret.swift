import Foundation
import Security

/// Tunnel configuration in the app-and-extension Keychain
public enum SharedTunnelSecret {
    public static let accessGroup = AppGroup.identifier
    public static let activeAccount = "active-tunnel"
    private static let service = "com.skaymer.gryonixnexus.tunnel.shared"

    public static func store(_ secret: String, account: String = activeAccount) -> Bool {
        let data = Data(secret.utf8)
        var attributes = query(account: account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        var status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update = [kSecValueData as String: data] as CFDictionary
            status = SecItemUpdate(query(account: account) as CFDictionary, update)
        }
        return status == errSecSuccess
    }

    public static func secret(account: String = activeAccount) -> String? {
        var request = query(account: account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(account: String = activeAccount) {
        SecItemDelete(query(account: account) as CFDictionary)
    }

    private static func query(account: String) -> [String: Any] {
        var base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
        #if os(macOS)
        base[kSecUseDataProtectionKeychain as String] = true
        #endif
        return base
    }
}
