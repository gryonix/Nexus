import AgentClient
import ServerControl
import ServiceCatalog
import SwiftUI

@available(macOS 15.0, *)
struct ModelKeysView: View {
    @ObservedObject var viewModel: DashboardViewModel

    /// What is typed, by provider id
    @State private var typed: [String: String] = [:]
    /// Which providers the server already holds a key for
    @State private var stored: Set<String> = []
    @State private var loading = true
    @State private var saving = false
    @State private var failure: String?
    @State private var saved = false

    private var host: String {
        let deployment = viewModel.deployment
        let running = deployment.host(running: .liteLLM)
        guard let node = deployment.nodes.first(where: { $0.sshHost == running }) else {
            return "single"
        }
        return DashboardViewModel.installReportKey(for: node, in: deployment)
    }

    var body: some View {
        CardList {
            Section {
                if loading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Reading the server's keys…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(LLMProvider.all) { provider in
                        providerRow(provider)
                    }
                }
            } header: {
                InfoSectionHeader("Model providers", note: "Each key is stored on the server, encrypted, and shared with your other devices. The gateway restarts by itself when a key changes.")
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    if saving {
                        ProgressView()
                    } else {
                        Text("Save")
                    }
                }
                .disabled(saving || loading || typed.values.allSatisfy(\.isEmpty))
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if saved {
                    Label("Saved. The gateway was restarted.", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if failure == nil {
                    Text("An empty field is left alone — only what you type is saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                // The honest boundary, in the words `vault.rs` uses for itself.
                InfoSectionHeader("How the keys are kept", note: "Encryption protects copies — a backup, a disk taken out of the machine. Anyone with root on this server can read the keys, because the gateway reads them too.")
            }
        }
        .navigationTitle(Text("API keys"))
        .task { await load() }
    }

    @ViewBuilder
    private func providerRow(_ provider: LLMProvider) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SecureTechnicalField(
                title: LocalizedStringKey(provider.displayName),
                text: Binding(
                    get: { typed[provider.id] ?? "" },
                    set: { typed[provider.id] = $0 }
                )
            )
            if stored.contains(provider.id) {
                Label("A key is stored. Type a new one to replace it.",
                      systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: provider.consoleURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let fetched = await AccessVault.fetch(deployment: viewModel.deployment)
        guard fetched.reachedServer else {
            failure = fetched.failure
            return
        }
        stored = Set(fetched.entries.compactMap {
            LLMProvider.provider(vaultSecretID: $0.serviceSecret)?.id
        })
    }

    private func save() async {
        saving = true
        defer { saving = false }
        saved = false
        failure = nil
        let now = Date()
        let writer = DeviceIdentity.uid
        let entries = LLMProvider.all.compactMap { provider -> Gryonixnexusd_V1_VaultEntry? in
            let key = (typed[provider.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return AccessVaultEntry.modelProviderKey(host: host, provider: provider,
                                                     key: key, at: now, writer: writer)
        }
        guard !entries.isEmpty else { return }
        guard await AccessVault.push(entries, deployment: viewModel.deployment) else {
            failure = UIL10n.string("The server could not be reached.")
            return
        }
        stored.formUnion(entries.compactMap {
            LLMProvider.provider(vaultSecretID: $0.serviceSecret)?.id
        })
        typed = [:]
        saved = true
    }
}
