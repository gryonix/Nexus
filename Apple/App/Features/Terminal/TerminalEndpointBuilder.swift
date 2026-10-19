import Foundation
import ServerControl
import ServerControlSSH

@available(macOS 15.0, *)
enum TerminalEndpointBuilder {
    enum Failure: LocalizedError {
        case notConfigured
        case unknownMachine

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return UIL10n.string("specify the server address and SSH user in the server settings")
            case .unknownMachine:
                return UIL10n.string("this deployment has no address for that machine")
            }
        }
    }

    /// Where to dial, plus which machine each address IS
    struct Target {
        var endpoint: TerminalEndpoint
        var pinTargets: [String: SSHHostID]
    }

    static func target(for deployment: Deployment, nodeID: UUID?) throws -> Target {
        let config = deployment.dashboardConfig
        guard config.isConnectable else { throw Failure.notConfigured }
        let pins = HostKeyPinStore(deploymentID: deployment.id)

        let entry = TerminalEndpoint(host: config.vpsHost,
                                     port: config.sshPort,
                                     pinnedHostKey: pins.pin(for: .vps))
        guard let nodeID, nodeID != deployment.nodes.first?.id else {
            return Target(endpoint: entry, pinTargets: [config.vpsHost: .vps])
        }
        guard let node = deployment.nodes.first(where: { $0.id == nodeID }) else {
            throw Failure.unknownMachine
        }

        let hopLogin = try appLogin(for: deployment, config: config)
        let hop = TerminalEndpoint.Hop(host: config.vpsHost,
                                       port: config.sshPort,
                                       pinnedHostKey: pins.pin(for: .vps),
                                       login: hopLogin)
        let endpoint = TerminalEndpoint(host: node.endpoint.host,
                                        port: node.endpoint.port,
                                        pinnedHostKey: pins.pin(for: hostID(of: node)),
                                        parent: hop)
        return Target(endpoint: endpoint,
                      pinTargets: [config.vpsHost: .vps, node.endpoint.host: hostID(of: node)])
    }

    static func appLogin(for deployment: Deployment,
                         config: DashboardConfig,
                         host: SSHHostID = .vps) throws -> TerminalLogin {
        if deployment.usesPasswordAuth {
            guard let password = DashboardPasswordStore(deploymentID: deployment.id).load(for: host) else {
                throw Failure.notConfigured
            }
            return TerminalLogin(username: config.sshUser, secret: .password(password))
        }
        let identity = try KeychainSSHIdentityStore(deploymentID: deployment.id).loadOrGenerate()
        return TerminalLogin(username: config.sshUser,
                             secret: .privateKeySeed(identity.privateKeySeed))
    }

    static func login(for profile: TerminalProfile, deployment: Deployment) throws -> TerminalLogin {
        switch profile.secret {
        case .password(let password):
            return TerminalLogin(username: profile.username, secret: .password(password))
        case .privateKeySeed(let seed):
            return TerminalLogin(username: profile.username, secret: .privateKeySeed(seed))
        case .appKey:
            let identity = try KeychainSSHIdentityStore(deploymentID: deployment.id).loadOrGenerate()
            return TerminalLogin(username: profile.username,
                                 secret: .privateKeySeed(identity.privateKeySeed))
        }
    }

    private static func hostID(of node: DeploymentNode) -> SSHHostID {
        if let slot = node.legacySlot { return SSHHostID(kind: .slot(slot)) }
        return SSHHostID(kind: .node(node.id))
    }
}
