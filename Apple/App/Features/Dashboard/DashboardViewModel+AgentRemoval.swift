import AgentClient
import Foundation
import ServerControl

extension DashboardViewModel {
    /// Takes the agent off the server; services and settings stay
    func removeAgent() async -> Deployment? {
        guard deployment.usesAgent, Self.agentTransportAvailable, #available(macOS 15.0, *) else { return nil }
        do {
            let runner = try await commandSession()
            let client = try await AgentConnection.client(deployment: deployment, runner: runner)
            _ = try await client.removeAgent()
        } catch AgentError.rpc(code: "not_found", message: _) {
            quickActionResult = QuickActionResult(
                message: UIL10n.string("This agent is too old to remove itself. Update it, then remove it."),
                isError: true)
            return nil
        } catch {
            quickActionResult = QuickActionResult(message: Self.message(for: error), isError: true)
            return nil
        }
        var updated = deployment
        updated.usesAgent = false
        applyDeployment(updated)
        agentVersion = nil
        agentCheck = nil
        homeDoors = [:]
        quickActionResult = QuickActionResult(
            message: UIL10n.string("The agent is being removed. Services, their data and the agent's settings stay on the server, and installing the agent again picks them up."),
            isError: false)
        return updated
    }
}
