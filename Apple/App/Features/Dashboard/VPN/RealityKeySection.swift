import ServiceCatalog
import SwiftUI

/// Gives VLESS / Reality a new server key
struct RealityKeySection: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var asking = false

    var body: some View {
        Section {
            Button(role: .destructive) {
                asking = true
            } label: {
                Label("New Reality key", systemImage: "key.horizontal")
            }
            .dangerTint()
            .confirmationDialog("Give VLESS / Reality a new key?", isPresented: $asking, titleVisibility: .visible) {
                Button("New key", role: .destructive) { Task { await renew() } }
                    .dangerTint()
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Devices keep their names, but every VLESS device needs its configuration again. This device gets it on its own.")
            }
        } header: {
            InfoSectionHeader("Server key", note: "Use it if the server's Reality key was shown to someone. A new key pair is made on the server; the old one stops working.")
        }
    }

    private func renew() async {
        guard await viewModel.renewRealityKey() else { return }
        await TunnelController.shared.refreshConfigurations(of: viewModel.deployment, protocolID: .xrayReality)
        await viewModel.loadVPNClients(protocol: .xrayReality)
    }
}
