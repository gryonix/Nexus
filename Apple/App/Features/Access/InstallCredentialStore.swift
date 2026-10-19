import Foundation
import ServerControl

struct InstallCredentialStore {
    private let deploymentID: UUID
    private let keychain: KeychainStore

    init(deploymentID: UUID, keychain: KeychainStore = KeychainStore()) {
        self.deploymentID = deploymentID
        self.keychain = keychain
    }

    private func account(_ host: SSHHostID) -> String {
        switch host.kind {
        case .slot(let slot):
            return "install-secret-\(deploymentID.uuidString)-\(slot.rawValue)"
        case .node(let id):
            return "install-secret-\(deploymentID.uuidString)-node-\(id.uuidString)"
        }
    }

    func secret(for host: SSHHostID) -> SSHSecret? {
        guard let data = (try? keychain.data(for: account(host))) ?? nil else { return nil }
        return try? JSONDecoder().decode(SSHSecret.self, from: data)
    }

    func save(_ secret: SSHSecret, for host: SSHHostID) throws {
        if case .appKey = secret {
            try keychain.delete(account(host))
            return
        }
        try keychain.set(JSONEncoder().encode(secret), for: account(host))
    }

    func delete(_ host: SSHHostID) {
        try? keychain.delete(account(host))
    }

    /// Everything this deployment stored, for the moment it is forgotten
    func deleteAll(nodeIDs: [UUID]) {
        delete(.vps)
        delete(.home)
        for id in nodeIDs {
            delete(SSHHostID(kind: .node(id)))
        }
    }
}
