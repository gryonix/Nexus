import AgentControl
import Foundation
import ServerControl

/// Which account each machine's terminal signs in as
@available(macOS 15.0, *)
@MainActor
final class TerminalMachineUsers: ObservableObject {
    @Published private(set) var users: [UUID: [SSHUserAccess]] = [:]
    @Published private(set) var chosen: [UUID: String] = [:]
    @Published private(set) var preparing: UUID?
    @Published var failure: String?

    let deployment: Deployment
    private let defaults: UserDefaults

    init(deployment: Deployment, defaults: UserDefaults = .standard) {
        self.deployment = deployment
        self.defaults = defaults
        for node in deployment.nodes {
            chosen[node.id] = defaults.string(forKey: Self.key(deployment.id, node.id))
        }
    }

    static func key(_ deploymentID: UUID, _ nodeID: UUID) -> String {
        "terminal.machineUser.\(deploymentID.uuidString).\(nodeID.uuidString)"
    }

    /// The account the app itself signs in with
    func appUser(of node: DeploymentNode) -> String {
        node.endpoint.user.isEmpty ? deployment.dashboardConfig.sshUser : node.endpoint.user
    }

    /// The chosen account, or the app's own
    func user(of node: DeploymentNode) -> String {
        chosen[node.id] ?? appUser(of: node)
    }

    func choose(_ name: String, for node: DeploymentNode) {
        let own = name == appUser(of: node)
        chosen[node.id] = own ? nil : name
        let key = Self.key(deployment.id, node.id)
        if own { defaults.removeObject(forKey: key) } else { defaults.set(name, forKey: key) }
    }

    /// Whether this machine's agent can list its accounts
    func lists(_ node: DeploymentNode) -> Bool {
        deployment.usesAgent && deployment.agentHosts.contains(node.sshHost)
    }

    /// Reads every machine's accounts
    func load() async {
        let key = await DashboardViewModel.devicePublicKey(for: deployment)
        for node in deployment.nodes where lists(node) {
            guard let operations = try? await operations(on: node),
                  let answer = try? await operations.sshUsers(loginUser: appUser(of: node), appPublicKey: key),
                  answer.isKnown else { continue }
            users[node.id] = answer.users
        }
    }

    /// Puts the app's key on the chosen account when missing
    func prepare(_ node: DeploymentNode) async -> Bool {
        let name = user(of: node)
        guard name != appUser(of: node),
              users[node.id]?.first(where: { $0.name == name })?.appKeyPresent != true else { return true }
        preparing = node.id
        defer { preparing = nil }
        do {
            let key = await DashboardViewModel.devicePublicKey(for: deployment)
            let answer = try await operations(on: node).authorizeAppKey(user: name, loginUser: appUser(of: node),
                                                                        appPublicKey: key)
            users[node.id] = answer.users
            failure = nil
            return true
        } catch {
            failure = UIL10n.string("Could not put the app's key on %1$@: %2$@", name,
                                    DashboardViewModel.message(for: error))
            return false
        }
    }

    private func operations(on node: DeploymentNode) async throws -> AgentSecurityOperations {
        let session = try await AgentConnection.open(deployment: deployment, shared: true, host: node.sshHost)
        return AgentSecurityOperations(client: session.client)
    }
}
