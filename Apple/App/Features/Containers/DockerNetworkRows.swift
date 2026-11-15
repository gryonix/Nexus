import AgentControl
import SwiftUI

struct DockerNetworkRows: View {
    let networks: [DockerNetworkSummary]
    let isLoading: Bool
    let remove: (DockerNetworkSummary) -> Void

    var body: some View {
        ForEach(networks) { network in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: network.name).lineLimit(1).truncationMode(.middle)
                    Text(status(network)).font(.caption)
                        .foregroundStyle(network.isRemovable ? Color.orange : Color.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: network.driver).font(.caption)
                    if !network.subnet.isEmpty { Text(verbatim: network.subnet).font(.caption2).monospaced() }
                }
                .foregroundStyle(.secondary)
            }
            .swipeActions(edge: .trailing) {
                if network.isRemovable {
                    Button(role: .destructive) { remove(network) } label: { Label("Remove", systemImage: "trash") }
                        .dangerTint()
                }
            }
        }
        if networks.isEmpty && !isLoading { Text("No networks").foregroundStyle(.secondary) }
    }

    private func status(_ network: DockerNetworkSummary) -> LocalizedStringKey {
        if network.isBuiltin { return "Built into Docker" }
        if network.isManaged { return "Used by an installed service" }
        if network.isInUse { return "Containers: \(network.containers)" }
        return "Unused"
    }
}
