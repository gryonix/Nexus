import AgentControl
import ServerControl
import ServiceCatalog
import SwiftUI
import VPNProfile
import VPNTunnel
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The card's tunnel rows, each opening a menu of alternatives
struct ThisDeviceRows: View {
    @ObservedObject var tunnel: TunnelController
    @ObservedObject var clients: ServerTunnelClients
    let profile: TunnelProfile
    @ObservedObject private var pins = TunnelEndpointPins.shared
    /// Servers that can host this device's tunnel
    let servers: [Deployment]

    private var server: Deployment? { servers.first { $0.id == profile.serverID } }

    var body: some View {
        Group {
            serverRow
            protocolRow
            configurationRow
            if #available(macOS 15.0, *) { dnsRow }
            endpointRow
        }
        .disabled(tunnel.status.isBusy || tunnel.isProvisioningThisDevice)
    }

    @ViewBuilder
    private var serverRow: some View {
        if servers.isEmpty {
            plainRow("Server", profile.serverName)
        } else {
            MenuRow("Server", value: profile.serverName) {
                ForEach(servers) { deployment in
                    VerbatimMenuChoice(deployment.name, picked: deployment.id == profile.serverID) {
                        switchServer(to: deployment)
                    }
                }
            }
        }
    }

    private func switchServer(to deployment: Deployment) {
        let available = ThisDeviceTunnelChoices.protocols(for: deployment)
        guard deployment.id != profile.serverID,
              let protocolID = ThisDeviceTunnelChoices.landingProtocol(among: available,
                                                                       keeping: profile.protocolID) else { return }
        Task { await tunnel.switchTo(deployment: deployment, protocolID: protocolID) }
    }

    @ViewBuilder
    private var protocolRow: some View {
        let current = ThisDeviceTunnelChoices.protocolLabel(profile.protocolID, obfuscated: profile.isObfuscated)
        if let server {
            MenuRow("Protocol", value: current) {
                ForEach(ThisDeviceTunnelChoices.protocols(for: server), id: \.self) { protocolID in
                    VerbatimMenuChoice(protocolLabel(protocolID), picked: protocolID == profile.protocolID) {
                        guard protocolID != profile.protocolID else { return }
                        Task { await tunnel.switchTo(deployment: server, protocolID: protocolID) }
                    }
                }
            }
        } else {
            plainRow("Protocol", current)
        }
    }

    /// Marked obfuscated when the tunnel kept for it is
    private func protocolLabel(_ protocolID: ServiceID) -> String {
        let kept = protocolID == profile.protocolID ? profile
            : ThisDeviceTunnelChoices.keptProfile(in: tunnel.profiles, serverID: profile.serverID,
                                                  protocolID: protocolID, ownName: TunnelController.thisDeviceName)
        return ThisDeviceTunnelChoices.protocolLabel(protocolID, obfuscated: kept?.isObfuscated ?? false)
    }

    @ViewBuilder
    private var configurationRow: some View {
        if let server {
            MenuRow("Configuration", value: profile.deviceName) {
                TunnelConfigurationChoices(tunnel: tunnel, clients: clients,
                                           deployment: server, protocolID: profile.protocolID)
            }
        } else {
            plainRow("Configuration", profile.deviceName)
        }
    }

    @available(macOS 15.0, *)
    private var dnsRow: some View {
        let listed = server.map { clients.devices(of: $0, profile.protocolID) } ?? []
        let shown = tunnel.wantedDNS[profile.id] ?? ThisDeviceTunnelChoices.dns(of: profile, listed: listed)
        return VPNDNSMenu(title: "DNS", addresses: shown,
                          local: clients.local(of: profile.serverID), owner: profile.id) { dns in
            Task {
                await tunnel.changeDNS(of: profile, to: dns)
                if let server { await clients.reload(server, profile.protocolID) }
            }
        }
        .equatable()
    }

    private var endpointRow: some View {
        let shown = pins.pin(for: profile)?.replacingHost(of: profile.endpoint) ?? profile.endpoint
        return MenuRow("Endpoint", value: shown, monospaced: true) {
            Section {
                Button("Copy") { Self.copy(shown) }
            } header: {
                Text(verbatim: profile.endpoint)
            }
            if TunnelEndpointPins.canPin(profile) { reachSection }
        }
    }

    private var reachSection: some View {
        let byAddress = pins.pin(for: profile) != nil
        return Section("Connect by") {
            MenuChoice("Domain name", picked: !byAddress) {
                Task { await tunnel.reachByAddress(false, profile: profile) }
            }
            MenuChoice("IP address", picked: byAddress) {
                Task { await tunnel.reachByAddress(true, profile: profile) }
            }
        }
    }

    private func plainRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent {
            Text(verbatim: value)
        } label: {
            Text(title)
        }
    }

    private static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
