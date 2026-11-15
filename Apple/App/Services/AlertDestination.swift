import Foundation
import ServerControl
import ServiceCatalog

/// Where a tapped server alert opens
struct AlertDestination: Equatable, Sendable {
    let deploymentID: UUID
    let tab: DashboardTab
    /// The failed service whose log opens
    let service: ServiceID?

    init(tab: DashboardTab, deploymentID: UUID, service: ServiceID? = nil) {
        self.tab = tab
        self.deploymentID = deploymentID
        self.service = service
    }

    init?(gnx: [String: Any], deploymentID: (String) -> UUID? = { RelayServers.deploymentID(of: $0) }) {
        guard let server = gnx["server_id"] as? String, !server.isEmpty,
              let id = deploymentID(server) else { return nil }
        self.deploymentID = id
        let kind = gnx["kind"] as? String ?? ""
        self.tab = Self.tab(forKind: kind)
        self.service = Self.service(forKind: kind, agentID: gnx["service"] as? String)
    }

    /// Only a service that went down opens its log
    static func service(forKind kind: String, agentID: String?) -> ServiceID? {
        guard kind == "gnx.alert.service", let agentID, !agentID.isEmpty else { return nil }
        return AgentServiceMapping.serviceIDs(forAgentIDs: [agentID]).first
    }

    /// Services and backups live in Apps; the rest in General
    static func tab(forKind kind: String) -> DashboardTab {
        let appKinds = ["gnx.alert.service", "gnx.alert.backup", "gnx.alert.drive_"]
        return appKinds.contains { kind.hasPrefix($0) } ? .operations : .general
    }
}
