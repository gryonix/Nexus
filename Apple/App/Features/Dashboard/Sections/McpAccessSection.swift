import AgentClient
import ServerControl
import ServiceCatalog
import SwiftUI

/// The read-only MCP door for outside AI agents
struct McpAccessSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject private var modules = ModuleSettings.shared
    @State private var state: Gryonixnexusd_V1_McpAccessState?
    @State private var newKey: UserSSHKey?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        if modules.isOn(.ai) {
            Section {
                Toggle("Read-only access for AI agents", isOn: Binding(get: { state?.enabled ?? false }, set: change))
                    .disabled(state == nil || busy)
                if let newKey { McpKeyHandout(key: newKey, config: config(for: newKey)) }
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            } header: {
                InfoSectionHeader("MCP") {
                    Text("Lets an AI agent on your computer read this server over SSH: services, state, metrics, security and logs, with secrets cut out. It cannot change anything.")
                    Text("It gets its own key that can only run this read-only door. Turning it off removes the key.")
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        state = try? await viewModel.mcpAccess()
    }

    private func change(_ on: Bool) {
        busy = true
        Task {
            do {
                if on {
                    let key = try SSHKeyGenerator.generate(kind: .ed25519, name: "gryonix-mcp")
                    state = try await viewModel.mcpAccess(set: true, publicKey: key.publicKey)
                    newKey = key
                } else {
                    state = try await viewModel.mcpAccess(set: false)
                    newKey = nil
                }
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }

    private func config(for key: UserSSHKey) -> String {
        DashboardViewModel.mcpClientConfig(name: viewModel.deployment.name, user: state?.users.first ?? "admin",
                                           host: viewModel.deployment.entry.host, keyPath: "~/.ssh/gryonix-mcp")
    }
}

/// The new key and client entry, shown once
private struct McpKeyHandout: View {
    let key: UserSSHKey
    let config: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save the key as ~/.ssh/gryonix-mcp (chmod 600) and add the entry to your AI client. The key is shown only now.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ShareLink(item: key.privateKeyPEM) { Label("Share the key", systemImage: "key") }
            Button("Copy the key", systemImage: "key.viewfinder") { SecretPasteboard.copy(key.privateKeyPEM) }
            Button("Copy the client entry", systemImage: "doc.on.doc") { AIClipboard.copy(config) }
            Text(verbatim: config).font(.caption.monospaced()).textSelection(.enabled)
        }
    }
}
