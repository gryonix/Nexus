import AgentClient
import AgentControl
import ServerControl

extension DashboardViewModel {
    /// Reads the MCP door, or sets it with a key
    func mcpAccess(set enabled: Bool? = nil, publicKey: String = "") async throws -> Gryonixnexusd_V1_McpAccessState {
        guard #available(macOS 15.0, *) else {
            throw ServerControlError.notConfigured(UIL10n.string("This needs a newer system."))
        }
        let runner = try await session()
        let client = try await AgentConnection.client(deployment: deployment, runner: runner)
        if let enabled {
            return try await agentGate.withSlot { try await client.setMcpAccess(enabled: enabled, publicKey: publicKey) }
        }
        return try await agentGate.withSlot { try await client.getMcpAccess() }
    }

    /// The MCP client entry for this server and key file
    static func mcpClientConfig(name: String, user: String, host: String, keyPath: String) -> String {
        let label = name.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return """
        {
          "mcpServers": {
            "gryonix-\(label.isEmpty ? "server" : label)": {
              "command": "ssh",
              "args": ["-i", "\(keyPath)", "-o", "BatchMode=yes", "\(user)@\(host)"]
            }
          }
        }
        """
    }
}
