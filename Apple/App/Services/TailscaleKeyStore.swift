import AgentControl
import ServiceCatalog

/// The user's Tailscale join key, kept in the Keychain
enum TailscaleKeyStore {
    private static let item = "tailscale-auth-key"

    static func load() async -> String? {
        await Task.detached {
            let stored = try? KeychainStore().string(for: item)
            return (stored?.isEmpty ?? true) ? nil : stored
        }.value
    }

    static func save(_ key: String) async throws {
        try await Task.detached { try KeychainStore().set(key, for: item) }.value
    }

    static func clear() async {
        await Task.detached { try? KeychainStore().delete(item) }.value
    }

    /// Adds the saved key when we run no control server
    static func apply(to context: inout AgentInstallContext, service: ServiceID,
                      installed: Set<ServiceID>) async {
        guard service == .tailscaleNode, !installed.contains(.headscale),
              let key = await load() else { return }
        context.settings[AgentInstallSettings.tailscaleAuthKeyKey] = key
    }
}
