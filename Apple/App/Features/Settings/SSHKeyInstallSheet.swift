import ServerControl
import SwiftUI

/// Pick servers, confirm, then append the key to authorized_keys
struct SSHKeyInstallSheet: View {
    let key: UserSSHKey
    @Environment(\.dismiss) private var dismiss
    @State private var deployments: [Deployment] = []
    @State private var chosen: Set<UUID> = []
    @State private var confirming = false
    @State private var running = false
    @State private var results: [UUID: String] = [:]

    var body: some View {
        NavigationStack {
            CardList {
                Section {
                    ForEach(deployments) { server in
                        row(server)
                    }
                } footer: {
                    Text("Only the servers you tick are changed. The key is added to the SSH user's authorized_keys if it is not there yet.")
                }
            }
            .screenTitle("Install on servers")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Install…") { confirming = true }
                        .disabled(chosen.isEmpty || running)
                }
            }
            .confirmationDialog(confirmTitle, isPresented: $confirming, titleVisibility: .visible) {
                Button("Install key") { Task { await install() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(confirmMessage)
            }
        }
        .task { deployments = (try? FileDeploymentStore().load()) ?? [] }
    }

    private var confirmTitle: String {
        UIL10n.string("Install %@ on %lld server(s)?", key.name, Int64(chosen.count))
    }

    private var confirmMessage: String {
        let names = deployments.filter { chosen.contains($0.id) }
            .map { "\($0.name) (\($0.entry.user))" }.joined(separator: "\n")
        return names + "\n\n" + key.fingerprint
    }

    private func row(_ server: Deployment) -> some View {
        Button {
            if chosen.contains(server.id) { chosen.remove(server.id) } else { chosen.insert(server.id) }
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(server.name)
                    Text(results[server.id] ?? "\(server.entry.user)@\(server.entry.host)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: chosen.contains(server.id) ? "checkmark.circle.fill" : "circle")
            }
        }
        .buttonStyle(.plain)
    }

    private func install() async {
        running = true
        defer { running = false }
        for server in deployments where chosen.contains(server.id) {
            results[server.id] = await install(on: server)
        }
    }

    private func install(on server: Deployment) async -> String {
        guard let command = AuthorizedKeysInstall.command(publicKeyLine: key.publicKey) else {
            return UIL10n.string("Failed")
        }
        do {
            let runner = try await DashboardSessionFactory.makeRunnerDetached(deployment: server)
            let result = try await runner.run(command, on: .vps, timeout: .seconds(20))
            switch AuthorizedKeysInstall.outcome(of: result) {
            case .added: return UIL10n.string("Key added")
            case .alreadyThere: return UIL10n.string("Key already there")
            case .failed: return UIL10n.string("Failed")
            }
        } catch {
            return error.localizedDescription
        }
    }
}
