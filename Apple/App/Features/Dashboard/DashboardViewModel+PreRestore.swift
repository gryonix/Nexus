import AgentControl
import Foundation
import ServerControl
import ServiceCatalog

extension DashboardViewModel {
    /// Reads one service's old restore copies
    func loadPreRestoreCopies(_ service: any ManagedService) async {
        guard let (operations, agentID) = try? await preRestoreOperations(for: service) else {
            preRestoreCopies[service.id] = []
            return
        }
        preRestoreCopies[service.id] = (try? await operations.copies(serviceID: agentID)) ?? []
    }

    func deletePreRestoreCopy(_ service: any ManagedService, copy: PreRestoreCopy) async {
        do {
            guard let (operations, _) = try await preRestoreOperations(for: service) else { return }
            preRestoreCopies[service.id] = try await operations.delete(copy)
            quickActionResult = QuickActionResult(
                message: UIL10n.string("%@ was deleted.", copy.name), isError: false)
        } catch {
            quickActionResult = QuickActionResult(message: Self.message(for: error), isError: true)
        }
    }

    private func preRestoreOperations(for service: any ManagedService) async throws
    -> (AgentPreRestoreOperations, String)? {
        guard deployment.usesAgent, Self.agentTransportAvailable,
              let agentID = AgentServiceMapping.agentID(for: service.id),
              #available(macOS 15.0, *) else { return nil }
        let runner = try await commandSession()
        let client = try await AgentConnection.client(deployment: deployment, runner: runner)
        let gate = AgentChannelGate.shared(for: deployment.id)
        return (AgentPreRestoreOperations(client: client, gate: gate), agentID)
    }
}
