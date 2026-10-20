import ServerControl
import SwiftUI

/// Where the VPN runs: at home or on the VPS
struct VPNPlacementSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var confirming = false
    @State private var moving = false
    @State private var recordResult: String?

    private var onRelay: Bool { viewModel.deployment.vpnRunsOnRelay }

    var body: some View {
        Section {
            LabeledContent {
                Text(onRelay ? "VPS" : "Home machine")
            } label: {
                Text("Runs on")
            }
            Button {
                confirming = true
            } label: {
                Label(onRelay ? "Move the VPN home" : "Move the VPN to the VPS",
                      systemImage: "arrow.left.arrow.right")
            }
            .disabled(moving)
            Button {
                record()
            } label: {
                Label(onRelay ? "The VPN already runs at home" : "The VPN already runs on the VPS",
                      systemImage: "checkmark.circle")
            }
            .disabled(moving)
            if let recordResult {
                Text(recordResult).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            InfoSectionHeader("Where the VPN runs", note: "At home, everything the VPN carries crosses your home connection twice, so its upload speed caps the VPN. On the VPS, internet traffic leaves straight from the VPS; only your own sites still go home through the tunnel.")
        } footer: {
            Text(onRelay
                 ? "The VPN panel's web page is not published while the VPN runs on the VPS — manage devices here."
                 : "Moving keeps every device's configuration: the same address, the same keys.")
        }
        .confirmationDialog(onRelay ? "Move the VPN home?" : "Move the VPN to the VPS?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button("Move") { move() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The VPN pauses for a few minutes. Devices keep their configurations and reconnect on their own.")
        }
    }

    private func record() {
        guard #available(macOS 15.0, *) else { return }
        moving = true
        Task {
            recordResult = await viewModel.recordVPNOnOtherMachine()
            moving = false
        }
    }

    private func move() {
        moving = true
        Task {
            await viewModel.moveVPN(toRelay: !onRelay)
            moving = false
        }
    }
}
