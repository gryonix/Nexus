import AgentClient
import AgentControl
import ServerControl

/// Asks the agent how many Vaultwarden accounts lack two-factor login
@available(macOS 15.0, *)
enum VaultwardenTwoFactorProbe {
    /// Nil when the agent could not answer
    static func read(deployment: Deployment) async -> VaultwardenTwoFactorStatus? {
        guard deployment.usesAgent else { return nil }
        do {
            let session = try await AgentConnection.open(deployment: deployment)
            defer { Task { await session.runner.disconnect() } }
            return VaultwardenTwoFactorStatus(try await session.client.vaultwardenTwoFactor())
        } catch {
            return nil
        }
    }
}
