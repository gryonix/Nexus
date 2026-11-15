import AgentClient
import AgentControl
import ServerControl
import ServiceCatalog

@available(macOS 15.0, *)
@MainActor
enum ServerModules {
    enum Failure: Error { case oldAgent }

    static func read(_ server: Deployment) async throws -> Set<String> {
        let client = try await client(server)
        do {
            return Set(try await client.getAppModules())
        } catch {
            throw Failure.oldAgent
        }
    }

    static func write(_ server: Deployment, _ on: Set<String>) async throws {
        let client = try await client(server)
        let kept = try await client.setAppModules(on.sorted())
        ModuleSettings.shared.adopt(server: server.id.uuidString, on: Set(kept))
    }

    private static func client(_ server: Deployment) async throws -> AgentClient {
        let runner = try await DashboardSessionFactory.makeRunnerDetached(deployment: server)
        return try await AgentConnection.client(deployment: server, runner: runner)
    }
}
