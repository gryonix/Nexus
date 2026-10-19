import Foundation

struct AccessCredential: Codable, Hashable {
    var login: String?
    var password: String?
    var token: String?
    /// When this device last changed it, and which installation did
    var updatedAt: Date?
    var updatedBy: String?

    var isEmpty: Bool {
        (login?.isEmpty ?? true) && (password?.isEmpty ?? true) && (token?.isEmpty ?? true)
    }
}

struct AccessCredentialStore {
    private let account: String
    private let keychain: KeychainStore

    init(deploymentID: UUID, keychain: KeychainStore = KeychainStore()) {
        self.account = "access-credentials-\(deploymentID.uuidString)"
        self.keychain = keychain
    }

    /// Keyed by ``key(host:title:)``
    func load() -> [String: AccessCredential] {
        guard let data = try? keychain.data(for: account),
              let dict = try? JSONDecoder().decode([String: AccessCredential].self, from: data) else {
            return [:]
        }
        return dict
    }

    func save(_ overrides: [String: AccessCredential]) {
        let pruned = overrides.filter { !$0.value.isEmpty }
        guard !pruned.isEmpty else {
            try? keychain.delete(account)
            return
        }
        if let data = try? JSONEncoder().encode(pruned) {
            try? keychain.set(data, for: account)
        }
    }

    func delete() {
        try? keychain.delete(account)
    }

    static func key(host: String, title: String) -> String { "\(host)|\(title)" }
}
