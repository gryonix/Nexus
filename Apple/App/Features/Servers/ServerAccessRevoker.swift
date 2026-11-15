import Foundation
import ServerControl

/// Takes this app's keys off a server before forgetting it
@MainActor
final class ServerAccessRevoker {
    /// One machine and what else lets someone in
    struct MachineCheck: Identifiable {
        let node: DeploymentNode
        let check: AppKeyRevocation.AccessCheck?
        var id: UUID { node.id }
    }

    let deployment: Deployment
    private let model: DashboardViewModel
    private let tunnels: TunnelController

    init(deployment: Deployment, tunnels: TunnelController? = nil) {
        self.deployment = deployment
        self.model = DashboardViewModel(deployment: deployment)
        self.tunnels = tunnels ?? .shared
    }

    private var keyBody: String? {
        let identity = try? KeychainSSHIdentityStore(deploymentID: deployment.id).load()
        return identity.flatMap { AppKeyRevocation.keyBody(of: $0.publicKeyOpenSSH) }
    }

    /// Reads every machine; throws when none answers
    func check() async throws -> [MachineCheck] {
        guard let body = keyBody else { return [] }
        let runner = try await model.session()
        var checks: [MachineCheck] = []
        var firstError: Error?
        for node in deployment.nodes {
            do {
                let result = try await runner.run(AppKeyRevocation.checkScript(keyBody: body),
                                                  on: node.sshHost, timeout: .seconds(30))
                checks.append(MachineCheck(node: node, check: AppKeyRevocation.parse(result.stdout)))
            } catch {
                firstError = firstError ?? error
                checks.append(MachineCheck(node: node, check: nil))
            }
        }
        if let firstError, checks.allSatisfy({ $0.check == nil }) { throw firstError }
        return checks
    }

    /// Removes own VPN entries and the key, returns failures
    func revoke(keepingKeyOn kept: Set<UUID>) async -> [String] {
        var failures = await removeOwnVPNDevices()
        if let body = keyBody, let runner = try? await model.session() {
            for node in AppKeyRevocation.removalOrder(deployment.nodes) where !kept.contains(node.id) {
                let result = try? await runner.run(AppKeyRevocation.removeScript(keyBody: body),
                                                   on: node.sshHost, timeout: .seconds(30))
                if result?.succeeded != true { failures.append(displayName(of: node)) }
            }
        }
        model.invalidateSession()
        return failures
    }

    /// The machine name, or the server name when unnamed
    func displayName(of node: DeploymentNode) -> String {
        node.name.isEmpty ? deployment.name : node.name
    }

    private func removeOwnVPNDevices() async -> [String] {
        guard deployment.usesAgent else { return [] }
        let own = tunnels.profiles.filter {
            $0.serverID == deployment.id && !$0.isForeign && TunnelController.isThisDevice($0.deviceName)
        }
        var failures: [String] = []
        for profile in own {
            await model.removeVPNClient(protocol: profile.protocolID, clientID: profile.deviceID)
            if model.quickActionResult?.isError == true { failures.append(profile.deviceName) }
        }
        return failures
    }
}
