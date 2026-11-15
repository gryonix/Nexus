import AgentControl
import ServerControl
import SwiftUI

/// What THIS machine runs, on the server's own screen
@available(macOS 15.0, *)
struct ServerContainersSection: View {
    let deployment: Deployment
    let edits: PendingRowEdits

    init(deployment: Deployment, edits: PendingRowEdits) {
        self.deployment = deployment
        self.edits = edits
        model = ContainersFleetViewModel.forServer(deployment.id)
    }

    // The server's own model, which outlives this segment — see `ContainersFleetViewModel.forServer`.
    @ObservedObject private var model: ContainersFleetViewModel
    @ObservedObject private var preferences = ContainersPreferences.shared
    @State private var inspecting: InspectedContainer?
    @State private var busyKey: String?
    @State private var tab = DockerTab.containers

    var body: some View {
        Section {
            DockerTabPicker(tab: $tab, server: deployment.id.uuidString)
            if tab == .containers {
                containerRows
            } else {
                DockerAssetsRows(deployment: deployment, tab: tab).id(tab)
            }
        } header: {
            InfoSectionHeader("Containers", note: "Everything running on this machine, including what this app did not install. The Containers tab is the same for every server at once — turn it on in Settings › Sections.")
        }
    }

    private var containerRows: some View {
        Group {
            ContainerGroupRows(deployment: deployment, model: model,
                               preferences: preferences, edits: edits,
                               inspecting: $inspecting, busyKey: $busyKey)
                .task { await model.load([deployment]) }
                .sheet(item: $inspecting) { inspected in
                    ContainerDetailSheet(container: inspected.container) { name in
                        try await model.detail(for: name, on: inspected.deployment)
                    }
                }
        }
    }
}
