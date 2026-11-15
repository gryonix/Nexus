import Foundation
import ServerControl

struct TerminalProfile: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var username: String
    var secret: SSHSecret
    /// Which machine of the deployment
    var nodeID: UUID?
    var keepAliveWithTmux: Bool

    init(id: UUID = UUID(), username: String, secret: SSHSecret, nodeID: UUID? = nil,
         keepAliveWithTmux: Bool = false) {
        self.id = id
        self.username = username
        self.secret = secret
        self.nodeID = nodeID
        self.keepAliveWithTmux = keepAliveWithTmux
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        username = try values.decode(String.self, forKey: .username)
        secret = try values.decode(SSHSecret.self, forKey: .secret)
        nodeID = try values.decodeIfPresent(UUID.self, forKey: .nodeID)
        keepAliveWithTmux = try values.decodeIfPresent(Bool.self, forKey: .keepAliveWithTmux) ?? false
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
