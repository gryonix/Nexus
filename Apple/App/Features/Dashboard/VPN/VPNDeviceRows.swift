import AgentControl
import ServerControl
import ServiceCatalog
import SwiftUI

/// The devices of one protocol, as plain list rows
struct VPNDeviceRows: View {
    @ObservedObject var viewModel: DashboardViewModel
    /// Which protocol's devices these are
    let selected: ServiceID
    let onShowConfiguration: (VPNClientDevice) -> Void
    let onRemove: (VPNClientDevice) -> Void

    var body: some View {
        switch viewModel.vpnClients {
        case .loaded(let clients):
            if clients.isEmpty {
                Text("No devices yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(clients) { device in
                    row(device)
                }
            }
        case .loading, .idle:
            HStack { Text("Loading…"); Spacer(); ProgressView().controlSize(.small) }
        case .failed(let message):
            Label(message, systemImage: HealthLevel.critical.systemImageName)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ device: VPNClientDevice) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                if !device.detail.isEmpty {
                    Text(verbatim: device.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                onShowConfiguration(device)
            } label: {
                Label("Configuration", systemImage: "qrcode")
            }
            .glassIconButtonStyle()
            .labelStyle(.iconOnly)
            ConfirmedRemoveButton(
                title: "Remove this device?",
                message: Text("\(device.name) stops connecting immediately. Its configuration cannot be restored — a replacement gets new keys.")
            ) {
                onRemove(device)
            }
            .dangerTint()
            .glassIconButtonStyle()
            .labelStyle(.iconOnly)
        }
    }
}

/// A device's configuration, held while its sheet is up
struct VPNShownConfiguration: Identifiable {
    /// The same device keeps the same sheet
    var id: String { device.id }
    let device: VPNClientDevice
    let value: VPNClientConfiguration
}

struct VPNPanelOnlySection: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        Section {
            Text(verbatim: viewModel.vpnProtocolNames)
                .font(.headline)
            Text(viewModel.vpnPanelOnlyReason)
                .font(.callout)
                .foregroundStyle(.secondary)
        } header: {
            Text("VPN")
        }
    }
}
