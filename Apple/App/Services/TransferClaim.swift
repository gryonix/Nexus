import AgentClient
import Foundation
import ServerControl

struct PendingTransferStore {
    private let account: String
    private let keychain: KeychainStore

    init(deploymentID: UUID, keychain: KeychainStore = KeychainStore()) {
        self.account = "ssh-transfer-\(deploymentID.uuidString)"
        self.keychain = keychain
    }

    func load() -> String? { (try? keychain.string(for: account)) ?? nil }

    func save(_ id: String) { try? keychain.set(id, for: account) }

    func clear() { try? keychain.delete(account) }
}

@available(macOS 15.0, *)
actor TransferClaim {
    static let shared = TransferClaim()

    private var claiming: Set<UUID> = []

    static func mintKey(for deployment: Deployment) async -> (seed: Data, id: String)? {
        guard let session = try? await AgentConnection.open(deployment: deployment, shared: true),
              let minted = try? await session.client.createTransfer(validMinutes: 60),
              minted.privateKeySeed.count == 32, !minted.transferID.isEmpty else { return nil }
        return (minted.privateKeySeed, minted.transferID)
    }

    /// Swaps the file's one-time key for this device's own, once
    func claimIfPending(session: AgentConnection.Session, deployment: Deployment) async {
        let pending = PendingTransferStore(deploymentID: deployment.id)
        guard let transferID = pending.load(), claiming.insert(deployment.id).inserted else { return }
        defer { claiming.remove(deployment.id) }
        guard let code = try? await AgentDeviceEnrolment.pairingCode(session: session, deployment: deployment)
        else { return }
        let own = AppSSHIdentity.generate()
        let uid = await Task.detached { DeviceIdentity.uid }.value
        let paired = try? await session.client.pairing(
            code: code, devicePublicKey: own.publicKeyOpenSSH, label: AgentDeviceEnrolment.deviceLabel,
            deviceUID: uid, authorizeSSHKey: true, transferID: transferID)
        guard paired?.sshKeyAuthorized == true else { return }
        let saved = (try? await Task.detached {
            try KeychainSSHIdentityStore(deploymentID: deployment.id).save(own)
        }.value) != nil
        if saved { pending.clear() }
    }
}
