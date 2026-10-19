import Foundation
import ServerControl

/// Keychain-backed storage of a deployment's SSH identity
struct KeychainSSHIdentityStore: SSHIdentityStore {
    private let account: String
    private let keychain: KeychainStore

    init(deploymentID: UUID, keychain: KeychainStore = KeychainStore()) {
        self.account = "ssh-identity-\(deploymentID.uuidString)"
        self.keychain = keychain
    }

    func load() throws -> AppSSHIdentity? {
        guard let seed = try keychain.data(for: account) else { return nil }
        return try AppSSHIdentity(privateKeySeed: seed)
    }

    func save(_ identity: AppSSHIdentity) throws {
        try keychain.set(identity.privateKeySeed, for: account)
    }

    func delete() throws {
        try keychain.delete(account)
    }
}

struct DashboardPasswordStore {
    private let deploymentID: UUID
    private let keychain: KeychainStore

    init(deploymentID: UUID, keychain: KeychainStore = KeychainStore()) {
        self.deploymentID = deploymentID
        self.keychain = keychain
    }

    private var legacyAccount: String { "ssh-password-\(deploymentID.uuidString)" }

    private func account(_ host: SSHHostID) -> String {
        switch host.kind {
        case .slot(let slot):
            return "ssh-password-\(deploymentID.uuidString)-\(slot.rawValue)"
        case .node(let id):
            return "ssh-password-\(deploymentID.uuidString)-node-\(id.uuidString)"
        }
    }

    func load(for host: SSHHostID = .vps) -> String? {
        if let own = (try? keychain.string(for: account(host))) ?? nil { return own }
        guard host == .vps,
              let inherited = (try? keychain.string(for: legacyAccount)) ?? nil else { return nil }
        try? keychain.set(inherited, for: account(host))
        return inherited
    }

    func save(_ password: String, for host: SSHHostID = .vps) throws {
        try keychain.set(password, for: account(host))
    }

    func delete(nodeIDs: [UUID] = []) {
        try? keychain.delete(legacyAccount)
        try? keychain.delete(account(.vps))
        try? keychain.delete(account(.home))
        for id in nodeIDs {
            try? keychain.delete(account(SSHHostID(kind: .node(id))))
        }
    }
}

/// Pinned SSH host keys (TOFU), per deployment
struct HostKeyPinStore {
    private let deploymentID: UUID
    private let keychain: KeychainStore

    init(deploymentID: UUID, keychain: KeychainStore = KeychainStore()) {
        self.deploymentID = deploymentID
        self.keychain = keychain
    }

    private func account(_ host: SSHHostID) -> String {
        switch host.kind {
        case .slot(let slot):
            return HostKeyPinAccounts.current(deployment: deploymentID, slot: slot)
        case .node(let id):
            return HostKeyPinAccounts.current(deployment: deploymentID, node: id)
        }
    }

    private func legacyAccount(_ host: SSHHostID) -> String? {
        host.slot.map { HostKeyPinAccounts.legacy(deployment: deploymentID, slot: $0) }
    }

    /// The pin; a read error yields a pin nothing matches
    func pin(for host: SSHHostID) -> String? {
        do {
            if let current = try keychain.string(for: account(host)) { return current }
            guard let legacy = legacyAccount(host),
                  let inherited = try keychain.string(for: legacy) else { return nil }
            try? keychain.set(inherited, for: account(host))
            return inherited
        } catch {
            return HostKeyPinAccounts.unreadable
        }
    }

    func store(_ key: String, for host: SSHHostID) {
        try? keychain.set(key, for: account(host))
    }

    func reset(_ host: SSHHostID) {
        try? keychain.delete(account(host))
        if let legacy = legacyAccount(host) { try? keychain.delete(legacy) }
    }

    func resetAll(nodeIDs: [UUID] = []) {
        reset(.vps)
        reset(.home)
        for id in nodeIDs { reset(.node(id)) }
        resetBastions()
    }

    // MARK: - Bastions

    private func bastionAccount(_ endpoint: String) -> String {
        "gryonixnexus.hostkey.bastion.\(deploymentID.uuidString).\(endpoint)"
    }

    func pin(forBastion endpoint: String) -> String? {
        do {
            return try keychain.string(for: bastionAccount(endpoint))
        } catch {
            return HostKeyPinAccounts.unreadable
        }
    }

    func store(_ key: String, forBastion endpoint: String) {
        try? keychain.set(key, for: bastionAccount(endpoint))
    }

    func resetBastions() {
        for account in keychain.accounts(withPrefix: bastionAccount("")) { try? keychain.delete(account) }
    }
}
