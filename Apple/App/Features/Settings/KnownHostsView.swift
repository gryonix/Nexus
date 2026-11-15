import ServerControl
import SwiftUI

struct KnownHostsView: View {
    @StateObject private var servers = ServerListViewModel()
    @StateObject private var model = KnownHostsViewModel()
    @State private var forgetting: KnownHostKey?

    var body: some View {
        CardList {
            if model.rows.isEmpty {
                Section { Text("No host keys saved yet").foregroundStyle(.secondary) }
            }
            ForEach(model.rows) { row in
                Section { rowView(row) }
            }
        }
        .screenTitle("Known hosts")
        .task {
            servers.load()
            model.load(servers.deployments)
        }
        .alert("Forget this host key?", isPresented: Binding(get: { forgetting != nil },
                                                             set: { if !$0 { forgetting = nil } })) {
            Button("Forget", role: .destructive) {
                if let row = forgetting { model.forget(row, in: servers.deployments) }
                forgetting = nil
            }
            .dangerTint()
            Button("Cancel", role: .cancel) { forgetting = nil }
        } message: {
            Text("The next connection to this machine will ask you to trust its key again.")
        }
    }

    @ViewBuilder
    private func rowView(_ row: KnownHostKey) -> some View {
        LabeledContent("Server", value: row.serverName)
        LabeledContent("Machine", value: row.machineName)
        LabeledContent("Address", value: row.endpoint)
        LabeledContent("Key type", value: row.keyType)
        VStack(alignment: .leading, spacing: 4) {
            Text("Fingerprint").font(.caption).foregroundStyle(.secondary)
            Text(verbatim: row.fingerprint).font(.caption.monospaced()).textSelection(.enabled)
        }
        Button("Forget", role: .destructive) { forgetting = row }.dangerTint()
    }
}
