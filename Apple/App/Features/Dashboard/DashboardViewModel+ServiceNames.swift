import AgentClient
import AgentControl
import Foundation
import ServerControl
import ServiceCatalog
import SwiftUI

extension DashboardViewModel {
    /// A service's given name here, or the catalog one
    func title(of service: any ManagedService) -> String {
        ServiceOwnNames.shared.title(service, server: deployment.id)
    }

    func title(of id: ServiceID) -> String {
        ServiceRegistry.service(id).map { title(of: $0) } ?? id.rawValue
    }

    /// Reads the server's names; sends up ones made without it
    @available(macOS 15.0, *)
    func syncServiceNames(_ client: AgentClient) async {
        let store = ServiceOwnNames.shared
        let server = deployment.id.uuidString
        guard var names = try? await client.getServiceNames() else { return }
        if store.unsent.contains(server) {
            for (id, name) in store.names(server: server) where names[id] != name {
                guard let kept = try? await client.setServiceName(id, name: name) else { return }
                names = kept
            }
        }
        store.adopt(server: server, names: names)
        objectWillChange.send()
    }

    /// Names a service on the server, or only here
    func renameService(_ service: ServiceID, to name: String) async {
        let store = ServiceOwnNames.shared
        let server = deployment.id.uuidString
        let kept = await serverNames(afterNaming: service, name)
        if let kept {
            store.adopt(server: server, names: kept)
        } else {
            store.set(name, service: service, server: server, sent: !deployment.usesAgent)
        }
        objectWillChange.send()
    }

    private func serverNames(afterNaming service: ServiceID, _ name: String) async -> [String: String]? {
        guard deployment.usesAgent, Self.agentTransportAvailable, #available(macOS 15.0, *) else { return nil }
        guard let runner = try? await session(),
              let client = try? await AgentConnection.client(deployment: deployment, runner: runner) else { return nil }
        return try? await client.setServiceName(service.rawValue, name: ServiceOwnNames.cleaned(name))
    }
}
