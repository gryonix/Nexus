import Foundation
import TVLink

/// Pairing keys in this app's Keychain
struct KeychainTVSecrets: TVSecretStoring {
    let keychain = KeychainStore()

    func store(_ secret: String, for account: String) throws {
        try keychain.set(secret, for: account)
    }

    func secret(for account: String) -> String? {
        (try? keychain.string(for: account)) ?? nil
    }

    func delete(_ account: String) {
        try? keychain.delete(account)
    }
}
