import Foundation
import ServerControl

struct TerminalProfile: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var username: String
    var secret: SSHSecret
    /// Which machine of the deployment
    var nodeID: UUID?

    init(id: UUID = UUID(), username: String, secret: SSHSecret, nodeID: UUID? = nil) {
        self.id = id
        self.username = username
        self.secret = secret
        self.nodeID = nodeID
    }

    /// What the list shows — the secret's own vocabulary
    var kindDescription: String { secret.kindDescription }
}

struct TerminalProfileStore {
    private let account: String
    private let keychain: KeychainStore

    init(deploymentID: UUID, keychain: KeychainStore = KeychainStore()) {
        self.account = "terminal-profiles-\(deploymentID.uuidString)"
        self.keychain = keychain
    }

    func load() -> [TerminalProfile] {
        guard let data = (try? keychain.data(for: account)) ?? nil else { return [] }
        return (try? JSONDecoder().decode([TerminalProfile].self, from: data)) ?? []
    }

    func save(_ profiles: [TerminalProfile]) throws {
        guard !profiles.isEmpty else {
            try keychain.delete(account)
            return
        }
        try keychain.set(JSONEncoder().encode(profiles), for: account)
    }

    func delete() {
        try? keychain.delete(account)
    }
}
