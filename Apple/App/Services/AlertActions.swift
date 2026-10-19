import AgentControl
import Foundation
import ServerControl
import UserNotifications

/// A button tapped on a server alert
struct AlertAction: Sendable, Equatable {
    enum Verb: String, Sendable {
        case block = "gnx.action.block"
        case restart = "gnx.action.restart"
    }

    let verb: Verb
    let server: String
    /// The machine's own name, as the alert printed it
    let host: String
    /// The address to block, or the container to restart
    let target: String

    init?(action: String, gnx: [String: Any]) {
        guard let verb = Verb(rawValue: action), let server = gnx["server_id"] as? String, !server.isEmpty
        else { return nil }
        let args = gnx["args"] as? [String] ?? []
        let target: String?
        switch verb {
        case .block: target = gnx["address"] as? String
        case .restart: target = args.count > 1 ? args[1] : nil
        }
        guard let target, !target.isEmpty else { return nil }
        self.verb = verb
        self.server = server
        self.host = args.first ?? ""
        self.target = target
    }
}

/// The buttons on server alerts and what they do
@MainActor
enum AlertActions {
    /// How long a block from an alert lasts
    static let banSeconds: TimeInterval = 24 * 3600

    /// The relay names each alert's category after its kind
    nonisolated static func categories() -> Set<UNNotificationCategory> {
        let block = UNNotificationAction(identifier: AlertAction.Verb.block.rawValue,
                                         title: UIL10n.string("Block address"),
                                         options: [.destructive, .authenticationRequired])
        let restart = UNNotificationAction(identifier: AlertAction.Verb.restart.rawValue,
                                           title: UIL10n.string("Restart"),
                                           options: [.authenticationRequired])
        return [
            UNNotificationCategory(identifier: "gnx.alert.ssh_login", actions: [block], intentIdentifiers: []),
            UNNotificationCategory(identifier: "gnx.alert.service", actions: [restart], intentIdentifiers: []),
        ]
    }

    static func perform(_ action: AlertAction) async {
        let outcome: String
        do {
            outcome = try await run(action)
        } catch {
            outcome = UIL10n.string("Could not do it: %@", error.localizedDescription)
        }
        await post(outcome, about: action)
    }

    private static func run(_ action: AlertAction) async throws -> String {
        guard #available(macOS 15.0, *), let target = RelayServers.target(of: action.server),
              let deployment = ((try? FileDeploymentStore().load()) ?? []).first(where: { $0.id == target.deploymentID })
        else { return UIL10n.string("This server is no longer in the app.") }
        let runner = try DashboardSessionFactory.makeRunner(deployment: deployment)
        defer { Task { await runner.disconnect() } }
        let client = try await AgentConnection.client(deployment: deployment, runner: runner,
                                                      host: target.host ?? deployment.servicesHost)
        switch action.verb {
        case .block:
            try await AgentSecurityOperations(client: client).setBan(true, value: action.target, duration: banSeconds)
            return UIL10n.string("%@ is blocked for 24 hours.", action.target)
        case .restart:
            let operations = AgentContainerOperations(client: client)
            let groups = try await operations.inventory().groups
            guard let group = groups.first(where: { $0.containers.contains { $0.name == action.target } }) else {
                return UIL10n.string("%@ is no longer on this server.", action.target)
            }
            for try await _ in operations.control(key: group.key, action: .restart) {}
            return UIL10n.string("%@ is restarted.", group.displayName)
        }
    }

    /// Posts how the tap ended beside the alert
    private static func post(_ outcome: String, about action: AlertAction) async {
        let content = UNMutableNotificationContent()
        content.title = action.host
        content.body = outcome
        content.threadIdentifier = action.server
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
