import ServerControl
import ServiceCatalog
import SwiftUI
import VPNTunnel

/// Connects this phone or Mac to the open server
struct ServerThisDeviceSection: View {
    let deployment: Deployment
    let protocolID: ServiceID
    @ObservedObject private var tunnel = TunnelController.shared

    private var carried: Bool {
        ThisDeviceTunnelChoices.protocols(for: deployment).contains(protocolID)
    }

    private var ownProfile: TunnelProfile? {
        tunnel.ownProfile(serverID: deployment.id, protocolID: protocolID)
    }

    private var running: Bool { tunnel.status.isActive || tunnel.status.isBusy }

    private var runsHere: Bool {
        guard running, let ownProfile else { return false }
        return tunnel.state.profileID == ownProfile.id
    }

    private var runsElsewhere: TunnelProfile? {
        running && !runsHere ? tunnel.active : nil
    }

    var body: some View {
        if carried {
            Section {
                if runsHere { status }
                action
            } header: {
                Text("This device")
            } footer: {
                footer
            }
        }
    }

    private var status: some View {
        HStack(spacing: 12) {
            TunnelPresentation.mark(tunnel.status, size: 22)
                .font(.system(size: 22))
                .foregroundStyle(TunnelPresentation.tint(tunnel.status,
                                                         isSimulated: tunnel.isDemonstration))
            Text(TunnelPresentation.title(tunnel.status))
            Spacer()
            if let since = tunnel.status.activeSince {
                TunnelSessionTimer(since: since, font: .subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var action: some View {
        Button {
            Task {
                if runsHere {
                    await tunnel.disconnect()
                } else {
                    await tunnel.connectHere(deployment: deployment, protocolID: protocolID)
                }
            }
        } label: {
            HStack {
                Label(actionTitle, systemImage: runsHere ? "stop.circle" : "power.circle")
                Spacer()
                if tunnel.isProvisioningThisDevice { ProgressView().controlSize(.small) }
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(runsHere ? Color.red : Color.accentColor)
        .disabled(tunnel.isProvisioningThisDevice || tunnel.status.isBusy)
    }

    private var actionTitle: LocalizedStringKey {
        if runsHere { return "Disconnect" }
        return runsElsewhere == nil ? "Connect this device" : "Move this device here"
    }

    @ViewBuilder private var footer: some View {
        if let error = tunnel.errorMessage {
            Text(verbatim: error)
        } else if let other = runsElsewhere {
            Text("Now connected through \(other.serverName).")
        } else if tunnel.isDemonstration {
            DemonstrationNotice(compact: true)
        }
    }
}
