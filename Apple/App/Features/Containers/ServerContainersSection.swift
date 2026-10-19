import AgentControl
import ServerControl
import SwiftUI

/// What THIS machine runs, on the server's own screen
@available(macOS 15.0, *)
struct ServerContainersSection: View {
    let deployment: Deployment

    init(deployment: Deployment) {
        self.deployment = deployment
        model = ContainersFleetViewModel.forServer(deployment.id)
    }

    // The server's own model, which outlives this segment — see `ContainersFleetViewModel.forServer`.
    @ObservedObject private var model: ContainersFleetViewModel
    @ObservedObject private var preferences = ContainersPreferences.shared
    @State private var inspecting: InspectedContainer?
    @State private var busyKey: String?

    var body: some View {
        Section {
            ContainerGroupRows(deployment: deployment, model: model,
                               preferences: preferences,
                               inspecting: $inspecting, busyKey: $busyKey)
                .task { await model.load([deployment]) }
                .sheet(item: $inspecting) { inspected in
                    ContainerDetailSheet(container: inspected.container) { name in
                        try await model.detail(for: name, on: inspected.deployment)
                    }
                }
        } header: {
            InfoSectionHeader("Containers", note: "Everything running on this machine, including what this app did not install. The Containers tab is the same for every server at once — turn it on in Settings › Sections.")
        }
    }
}
