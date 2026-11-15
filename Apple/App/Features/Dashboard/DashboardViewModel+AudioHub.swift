import AgentClient
import AgentControl
import ServerControl

extension DashboardViewModel {
    /// One call to the hub's API; non-2xx throws
    @discardableResult
    func odio(_ method: String, _ path: String, body: String = "") async throws -> String {
        guard #available(macOS 15.0, *) else {
            throw ServerControlError.notConfigured(UIL10n.string("This needs a newer system."))
        }
        let runner = try await session()
        let client = try await AgentConnection.client(deployment: deployment, runner: runner)
        let reply = try await agentGate.withSlot { try await client.odioCall(method: method, path: path, body: body) }
        guard (200..<300).contains(reply.status) else {
            throw ServerControlError.notConfigured(reply.body.isEmpty ? "odio-api: \(reply.status)" : reply.body)
        }
        return reply.body
    }

    /// Everything the hub's control screen shows
    func fetchAudioHub() async throws -> AudioHubState {
        var state = AudioHubState()
        AudioHubParser.apply(server: try await odio("GET", "/audio/server"), to: &state)
        state.outputs = AudioHubParser.outputs(try await odio("GET", "/audio/outputs"))
        state.players = AudioHubParser.players(try await odio("GET", "/players"))
        state.services = AudioHubParser.services(try await odio("GET", "/services"))
        if let bluetooth = try? await odio("GET", "/bluetooth") {
            AudioHubParser.apply(bluetooth: bluetooth, to: &state)
        }
        return state
    }
}
