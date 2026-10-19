import AgentClient
import Foundation

extension DashboardViewModel {
    /// Switches automatic agent updates on every machine of the server
    @available(macOS 15.0, *)
    func setAgentAutoUpdate(_ enabled: Bool) async {
        guard let runner = try? await commandSession() else { return }
        for host in deployment.agentHosts {
            guard let client = try? await AgentConnection.client(deployment: deployment, runner: runner, host: host),
                  let status = try? await client.setAgentAutoUpdate(enabled) else { continue }
            if host == deployment.servicesHost { selfUpdateStatus = status }
        }
    }
}
