import AgentControl
import ServerControl
import ServiceCatalog
import SwiftUI
import VPNProfile
import VPNTunnel

/// "This device" — the tunnel THIS Mac or phone is running
struct ThisDeviceCard: View {
    @ObservedObject var tunnel: TunnelController
    @ObservedObject private var pins = TunnelEndpointPins.shared
    var highlighted = false

    /// For the server/protocol menu on the Connect row
    @StateObject private var servers = ServerListViewModel()
    @StateObject private var clients = ServerTunnelClients()

    var body: some View {
        Section {
            header
            if let profile = tunnel.active ?? tunnel.selected {
                detail(profile)
            }
            button
        } header: {
            InfoSectionHeader("This device") {
                Text("This is the tunnel gryonixNexus brings up itself — pick a server and protocol, press Connect, and it appears here with a live timer and the month's traffic.")
                if tunnel.isDemonstration {
                    Text("This build is a demonstration: it walks through connecting and counts traffic but carries none. A real tunnel needs the app signed with the Network Extension capability.")
                }
            }
        } footer: {
            footer
        }
        .listRowBackground(highlighted ? Color.accentColor.opacity(0.08) : nil)
        .task {
            servers.load()
            await clients.load(manageableServers)
        }
        .task(id: shownServer?.id) {
            if let shownServer { await clients.loadLocalDNS(of: shownServer) }
        }
    }

    /// The server of the tunnel the card shows
    private var shownServer: Deployment? {
        let serverID = (tunnel.active ?? tunnel.selected)?.serverID
        return manageableServers.first { $0.id == serverID }
    }

    private var manageableServers: [Deployment] {
        ThisDeviceTunnelChoices.manageableServers(in: servers.deployments)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 12) {
            TunnelPresentation.mark(tunnel.status, size: 26)
                .font(.system(size: 26))
                .foregroundStyle(TunnelPresentation.tint(tunnel.status,
                                                         isSimulated: tunnel.isDemonstration))
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(TunnelPresentation.title(tunnel.status))
                    .font(.headline)
                if let since = tunnel.status.activeSince {
                    TunnelSessionTimer(since: since, font: .subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if let reason = tunnel.status.failureReason.map(VPNText.failureReason) {
                    Text(verbatim: reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if tunnel.status.isBusy || tunnel.isProvisioningThisDevice {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func detail(_ profile: TunnelProfile) -> some View {
        ThisDeviceRows(tunnel: tunnel, clients: clients, profile: profile, servers: manageableServers)
        if tunnel.status.isActive {
            LabeledContent {
                Text(verbatim: TunnelPresentation.traffic(tunnel.state.statistics))
                    .monospacedDigit()
            } label: {
                Text("This session")
            }
        }
        LabeledContent {
            Text(verbatim: TunnelPresentation.traffic(tunnel.trafficThisMonth()))
                .monospacedDigit()
        } label: {
            Text("This month")
        }
    }

    private var button: some View {
        HStack(spacing: 0) {
            if !manageableServers.isEmpty {
                Color.clear.frame(width: addTunnelButtonWidth, height: 1)
            }

            Button {
                Task { await tunnel.toggle() }
            } label: {
                Text(tunnel.status.isActive || tunnel.status == .connecting
                     ? "Disconnect" : "Connect")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(tunnel.status.isActive ? Color.red : Color.accentColor)
            .disabled(tunnel.selected == nil || tunnel.status.isBusy)

            if !manageableServers.isEmpty {
                addTunnelMenu
                    .disabled(tunnel.status.isBusy)
            }
        }
    }

    private let addTunnelButtonWidth: CGFloat = 44

    private var addTunnelMenu: some View {
        TunnelConfigurationMenu(tunnel: tunnel, clients: clients,
                                servers: manageableServers, width: addTunnelButtonWidth)
    }

    /// The chosen tunnel cannot reach its server's admin panels
    private var panelsClosedOverThisTunnel: Bool {
        guard let profile = tunnel.active ?? tunnel.selected,
              profile.protocolID != .wireguardVPN,
              let server = servers.deployments.first(where: { $0.id == profile.serverID }) else { return false }
        return server.services.contains(.vpnPanel)
    }

    private var pinned: EndpointPin? {
        (tunnel.active ?? tunnel.selected).flatMap(pins.pin(for:))
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if tunnel.profiles.isEmpty {
                Text(TunnelPresentation.noProfilesNotice)
            }
            if tunnel.isDemonstration {
                DemonstrationNotice(compact: true)
            }
            if panelsClosedOverThisTunnel {
                Label("Admin panels open only over WireGuard. This tunnel carries internet traffic.",
                      systemImage: "lock")
                    .foregroundStyle(.secondary)
            }
            if let pinned {
                Label(UIL10n.string("Connects to %@ directly, without looking up the domain. If the server's address changes, switch back to the domain name.", pinned.address),
                      systemImage: "pin")
                    .foregroundStyle(.secondary)
            }
            if let error = tunnel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
