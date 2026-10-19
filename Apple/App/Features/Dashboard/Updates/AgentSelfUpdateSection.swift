import AgentClient
import ServerControl
import SwiftUI

struct AgentSelfUpdateSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var confirming = false

    var body: some View {
        if let status = viewModel.selfUpdateStatus {
            autoUpdateSection(status)
        }
        if let status = viewModel.selfUpdateStatus, status.updateAvailable {
            Section {
                Label {
                    Text(verbatim: UIL10n.string("gryonixnexusd %@ is published.", status.availableVersion))
                } icon: {
                    Image(systemName: "arrow.down.circle").foregroundStyle(.blue)
                }
                if viewModel.isApplyingSelfUpdate {
                    HStack {
                        ProgressView().controlSize(.small)
                        if let progress = viewModel.selfUpdateProgress {
                            Text(verbatim: progress).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Button {
                        confirming = true
                    } label: {
                        Label("Update the agent now", systemImage: "bolt.fill")
                    }
                }
                if let error = viewModel.selfUpdateError {
                    Label {
                        Text(verbatim: error)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .font(.footnote)
                }
            } header: {
                InfoSectionHeader("Agent update") {
                    Text("Downloads the published source, rebuilds the agent on the server, and restarts it — separately from this app's own release. The agent stops answering for a few seconds while it restarts.")
                }
            }
            .alert(
                Text("Update the agent?"),
                isPresented: $confirming
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Update") {
                    Task { await viewModel.applySelfUpdate() }
                }
            } message: {
                Text(verbatim: UIL10n.string(
                    "Rebuilds gryonixnexusd %@ on the server and restarts it. The agent stops answering for a few seconds; nothing else on the server is affected.",
                    status.availableVersion))
            }
        }
    }

    private func autoUpdateSection(_ status: Gryonixnexusd_V1_AgentUpdateStatus) -> some View {
        Section {
            Toggle("Update the agent by itself", isOn: Binding(
                get: { status.autoUpdate },
                set: { enabled in
                    guard #available(macOS 15.0, *) else { return }
                    Task { await viewModel.setAgentAutoUpdate(enabled) }
                }))
        } header: {
            InfoSectionHeader("Agent updates") {
                Text("When a new agent is published, every machine of this server installs it once nothing else is running. A version that does not start is put back by itself.")
            }
        }
    }
}
