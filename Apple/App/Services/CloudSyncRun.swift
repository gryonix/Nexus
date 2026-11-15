import CryptoKit
import Foundation
import ServerControl
import VPNTunnel

/// An imported tunnel as it travels through iCloud
struct SyncedTunnel: Codable {
    var profile: TunnelProfile
    var secret: String
}

/// One pass over servers and tunnels against iCloud's copy
@MainActor
final class CloudSyncRun {
    static let serverPrefix = "server."
    static let tunnelPrefix = "tunnel."

    let mode: CloudSyncMode
    private let key: SymmetricKey?
    private let items: any CloudItemStoring
    private let store: any DeploymentStore
    private let remote: [String: Data]
    private(set) var marks: [String: CloudSyncMark]
    private(set) var changedServers = false
    private(set) var locked = 0
    private(set) var failure: String?

    init(mode: CloudSyncMode, key: SymmetricKey?, items: any CloudItemStoring, store: any DeploymentStore,
         remote: [String: Data], marks: [String: CloudSyncMark]) {
        self.mode = mode
        self.key = key
        self.items = items
        self.store = store
        self.remote = remote
        self.marks = marks
    }

    // MARK: - Servers

    func servers() {
        let locals = ((try? store.load()) ?? []).filter { !DemoServer.isDemo($0) }
        let byID = Dictionary(locals.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        for id in ids(prefix: Self.serverPrefix, local: Set(byID.keys)) {
            server(id, local: byID[id])
        }
    }

    private func server(_ id: String, local: Deployment?) {
        let account = Self.serverPrefix + id
        let payload = local.flatMap(serverPayload)
        let envelope = remote[account].flatMap(CloudSyncEnvelope.decode)
        switch CloudSyncPlanner.decide(remote: envelope, localHash: payload.map(hashed), mark: marks[account]) {
        case .apply: if let envelope { applyServer(envelope, account: account) }
        case .delete:
            if let local { forget(local) }
            if let envelope { marks[account] = CloudSyncMark(hash: "", at: envelope.modifiedAt) }
        case .push: if let payload { push(payload, account: account) }
        case .pushDeletion: pushDeletion(account)
        case .dismiss: dismiss(account)
        case .nothing: break
        }
    }

    /// The server's transfer bundle, without secrets unless keys sync
    func serverPayload(_ deployment: Deployment) -> Data? {
        var transfer = DeploymentTransferService.export(deployment)
        if !mode.includesKeys { transfer = Self.withoutSecrets(transfer) }
        return try? DeploymentTransferService.encode(transfer)
    }

    static func withoutSecrets(_ transfer: DeploymentTransfer) -> DeploymentTransfer {
        var stripped = transfer
        stripped.sshIdentitySeed = nil
        stripped.sshTransferID = nil
        stripped.dashboardPassword = nil
        stripped.dashboardPasswords = nil
        stripped.wireGuardSeeds = [:]
        stripped.reports = []
        stripped.accessCredentials = nil
        stripped.configuration = nil
        return stripped
    }

    private func applyServer(_ envelope: CloudSyncEnvelope, account: String) {
        guard let plain = opened(envelope),
              let transfer = try? DeploymentTransferService.decode(plain) else { return }
        do {
            let applied = try DeploymentTransferService.apply(transfer, store: store)
            changedServers = true
            let hash = serverPayload(applied).map(hashed) ?? ""
            marks[account] = CloudSyncMark(hash: hash, at: envelope.modifiedAt)
        } catch {
            failure = error.localizedDescription
        }
    }

    private func forget(_ deployment: Deployment) {
        try? DeploymentEraser.removeEntry(deployment, store: store)
        DeploymentEraser.eraseSecrets(deploymentID: deployment.id, nodeIDs: deployment.nodes.map(\.id))
        changedServers = true
    }

    // MARK: - Imported tunnels

    func tunnels(_ controller: TunnelController) async {
        let locals = Dictionary(controller.importedForSync().map { ($0.profile.id.uuidString, $0) },
                                uniquingKeysWith: { first, _ in first })
        for id in ids(prefix: Self.tunnelPrefix, local: Set(locals.keys)) {
            await tunnel(id, local: locals[id], controller: controller)
        }
    }

    private func tunnel(_ id: String, local: SyncedTunnel?, controller: TunnelController) async {
        let account = Self.tunnelPrefix + id
        let payload = local.flatMap { try? Self.sortedEncoder.encode($0) }
        let envelope = remote[account].flatMap(CloudSyncEnvelope.decode)
        switch CloudSyncPlanner.decide(remote: envelope, localHash: payload.map(hashed), mark: marks[account]) {
        case .apply:
            guard let envelope, let plain = opened(envelope),
                  let tunnel = try? JSONDecoder().decode(SyncedTunnel.self, from: plain) else { return }
            do {
                try controller.adoptSynced(tunnel)
                marks[account] = CloudSyncMark(hash: hashed(plain), at: envelope.modifiedAt)
            } catch {
                failure = error.localizedDescription
            }
        case .delete:
            if let local { await controller.remove(local.profile) }
            if let envelope { marks[account] = CloudSyncMark(hash: "", at: envelope.modifiedAt) }
        case .push: if let payload { push(payload, account: account) }
        case .pushDeletion: pushDeletion(account)
        case .dismiss: dismiss(account)
        case .nothing: break
        }
    }

    // MARK: - Shared steps

    private static var sortedEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func ids(prefix: String, local: Set<String>) -> [String] {
        let known = remote.keys.filter { $0.hasPrefix(prefix) } + marks.keys.filter { $0.hasPrefix(prefix) }
        return local.union(known.map { String($0.dropFirst(prefix.count)) }).sorted()
    }

    /// The payload hash, tied to the current mode
    private func hashed(_ payload: Data) -> String {
        CloudSyncPlanner.hash(payload + Data(mode.rawValue.utf8))
    }

    private func opened(_ envelope: CloudSyncEnvelope) -> Data? {
        guard envelope.sealed else { return envelope.payload }
        guard let key, let plain = try? CloudSyncSeal.open(envelope.payload, key: key) else {
            locked += 1
            return nil
        }
        return plain
    }

    private func push(_ payload: Data, account: String) {
        do {
            let sealed = mode.usesPassword
            guard !sealed || key != nil else { return locked += 1 }
            let body = try key.map { sealed ? try CloudSyncSeal.seal(payload, key: $0) : payload } ?? payload
            let envelope = CloudSyncEnvelope(modifiedAt: Date(), sealed: sealed, payload: body)
            try items.set(envelope.encoded(), for: account)
            marks[account] = CloudSyncMark(hash: hashed(payload), at: envelope.modifiedAt)
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Remembers a removal made on this device only
    private func dismiss(_ account: String) {
        marks[account] = CloudSyncMark(hash: "", at: marks[account]?.at ?? Date(), dismissed: true)
    }

    private func pushDeletion(_ account: String) {
        let envelope = CloudSyncEnvelope(modifiedAt: Date(), deleted: true)
        do {
            try items.set(envelope.encoded(), for: account)
            marks[account] = CloudSyncMark(hash: "", at: envelope.modifiedAt)
        } catch {
            failure = error.localizedDescription
        }
    }
}
