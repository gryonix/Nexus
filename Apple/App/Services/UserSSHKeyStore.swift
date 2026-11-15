import Foundation
import ServerControl

/// Keychain-backed list of the user's own SSH keys
@MainActor
final class UserSSHKeyStore: ObservableObject {
    static let shared = UserSSHKeyStore()
    private static let account = "user-ssh-keys"

    @Published private(set) var keys: [UserSSHKey] = []
    @Published var errorMessage: String?
    private let keychain: KeychainStore

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
        reload()
    }

    func reload() {
        guard let data = (try? keychain.data(for: Self.account)) ?? nil,
              let decoded = try? JSONDecoder().decode([UserSSHKey].self, from: data) else {
            keys = []
            return
        }
        keys = decoded
    }

    func add(_ key: UserSSHKey) {
        persist(keys + [key])
    }

    func rename(_ key: UserSSHKey, to name: String) {
        var renamed = key
        renamed.name = name
        persist(keys.map { $0.id == key.id ? renamed : $0 })
    }

    func delete(_ key: UserSSHKey) {
        persist(keys.filter { $0.id != key.id })
    }

    private func persist(_ updated: [UserSSHKey]) {
        do {
            try keychain.set(try JSONEncoder().encode(updated), for: Self.account)
            keys = updated
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
