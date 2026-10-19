import Foundation
import ServerControl
import ServiceCatalog

@MainActor
final class ServerListViewModel: ObservableObject {
    @Published var deployments: [Deployment] = []
    @Published var errorMessage: String?

    private let store: any DeploymentStore

    private var demoAppearance: [UUID: Deployment] = [:]

    init(store: any DeploymentStore = FileDeploymentStore()) {
        self.store = store
    }

    func load() {
        #if DEBUG
        if let demo = DemoDeployments.fromEnvironment() {
            deployments = demo
            errorMessage = nil
            return
        }
        #endif
        do {
            var loaded = try store.load()
            if let migrated = LegacyDashboardMigrator.migrateIfNeeded(store: store) {
                loaded.append(migrated)
            }
            deployments = loaded
            applyDemoRule()
            errorMessage = nil
        } catch {
            errorMessage = UIL10n.string("Failed to load the server list: %@", error.localizedDescription)
        }
    }

    /// Persists a new server order
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        deployments.move(fromOffsets: source, toOffset: destination)
        do {
            try store.save(deployments.filter { !DemoServer.isBuiltIn($0) })
            errorMessage = nil
        } catch {
            errorMessage = UIL10n.string("Failed to save the server order: %@", error.localizedDescription)
        }
    }

    func move(_ moved: UUID, before target: UUID) {
        guard moved != target,
              let from = deployments.firstIndex(where: { $0.id == moved }),
              let to = deployments.firstIndex(where: { $0.id == target }) else { return }
        move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    func upsert(_ deployment: Deployment) {
        do {
            try store.upsert(deployment)
            if let index = deployments.firstIndex(where: { $0.id == deployment.id }) {
                deployments[index] = deployment
            } else {
                deployments.append(deployment)
            }
            applyDemoRule()
            errorMessage = nil
        } catch {
            errorMessage = UIL10n.string("Failed to save the server: %@", error.localizedDescription)
        }
    }

    func updateAppearance(_ deployment: Deployment) {
        if DemoServer.isBuiltIn(deployment) { demoAppearance[deployment.id] = deployment }
        if let index = deployments.firstIndex(where: { $0.id == deployment.id }) {
            deployments[index] = deployment
        } else {
            deployments.append(deployment)
        }
        applyDemoRule()
        guard !DemoServer.isBuiltIn(deployment) else { return }
        let store = self.store
        Task.detached(priority: .utility) { [weak self] in
            do {
                try store.upsert(deployment)
                await self?.report(nil)
            } catch {
                let message = UIL10n.string("Failed to save the server: %@",
                                            error.localizedDescription)
                await self?.report(message)
            }
        }
    }

    private func report(_ message: String?) {
        errorMessage = message
    }

    /// The server file, sealed with the passphrase
    func exportData(for deployment: Deployment, passphrase: String) async -> Data? {
        let key = await transferKey(for: deployment)
        do {
            let plain = try DeploymentTransferService.encode(
                DeploymentTransferService.export(deployment, transferKey: key))
            return try TransferSeal.seal(plain, passphrase: passphrase)
        } catch {
            errorMessage = UIL10n.string("Failed to export the server: %@", error.localizedDescription)
            return nil
        }
    }

    /// A one-time key reaches one machine only
    static func usesOneTimeKey(for deployment: Deployment) -> Bool {
        !deployment.isMultiHost
    }

    private func transferKey(for deployment: Deployment) async -> (seed: Data, id: String)? {
        guard Self.usesOneTimeKey(for: deployment) else { return nil }
        guard #available(macOS 15.0, *) else { return nil }
        return await TransferClaim.mintKey(for: deployment)
    }

    func apply(_ transfer: DeploymentTransfer) {
        do {
            let deployment = try DeploymentTransferService.apply(transfer, store: store)
            if let index = deployments.firstIndex(where: { $0.id == deployment.id }) {
                deployments[index] = deployment
            } else {
                deployments.append(deployment)
            }
            applyDemoRule()
            errorMessage = nil
        } catch {
            errorMessage = UIL10n.string("Failed to import the server: %@", error.localizedDescription)
        }
    }

    func delete(_ deployment: Deployment) {
        do {
            try DeploymentEraser.removeEntry(deployment, store: store)
            DemoServer.forget(installed: deployment.id)
            deployments.removeAll { $0.id == deployment.id }
            applyDemoRule()
            errorMessage = nil
            let id = deployment.id
            let nodeIDs = deployment.nodes.map(\.id)
            Task.detached(priority: .utility) {
                DeploymentEraser.eraseSecrets(deploymentID: id, nodeIDs: nodeIDs)
            }
        } catch {
            errorMessage = UIL10n.string("Failed to delete the server: %@", error.localizedDescription)
        }
    }

    private func applyDemoRule() {
        DemoServer.releaseReal(deployments)
        let real = deployments.filter { !DemoServer.isDemo($0) }
        guard real.isEmpty || !LicenseStore.isUnlocked, DemoServer.isEnabled else {
            deployments = real
            return
        }
        let installed = deployments.filter { DemoServer.isInstalled($0.id) && !DemoServer.isBuiltIn($0.id) }
        deployments = DemoServer.deployments().map { demoAppearance[$0.id] ?? $0 } + installed
    }
}
