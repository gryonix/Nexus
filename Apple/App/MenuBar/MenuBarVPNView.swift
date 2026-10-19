#if os(macOS)
import AgentControl
import AppKit
import ServerControl
import ServiceCatalog
import SwiftUI
import VPNTunnel

struct MenuBarVPNView: View {
    @ObservedObject var tunnel: TunnelController
    @ObservedObject private var settings = MenuBarSettings.shared
    @StateObject private var servers = ServerListViewModel()
    @Environment(\.openURL) private var openURL

    private var pairs: [ThisDeviceTunnelChoices.Pair] {
        ThisDeviceTunnelChoices.pairs(in: servers.deployments)
    }

    /// Closes the panel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headline
            Divider().padding(.vertical, 10)
            if tunnel.profiles.isEmpty && pairs.isEmpty {
                empty
            } else {
                detail
                connectButton
                if !pairs.isEmpty { picker }
            }
            Divider().padding(.vertical, 10)
            footer
        }
        .padding(14)
        .frame(width: 320)
        .task { servers.load() }
    }

    // MARK: - Pieces

    private var headline: some View {
        HStack(spacing: 10) {
            TunnelPresentation.menuBarMark(tunnel.status, size: 22)
                .font(.system(size: 22))
                .foregroundStyle(TunnelPresentation.tint(tunnel.status,
                                                         isSimulated: tunnel.isDemonstration))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(TunnelPresentation.title(tunnel.status))
                    .font(.headline)
                if let since = tunnel.status.activeSince {
                    TunnelSessionTimer(since: since, font: .caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if let profile = tunnel.selected {
                    Text(verbatim: profile.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if tunnel.status.isBusy || tunnel.isProvisioningThisDevice {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let profile = tunnel.active ?? tunnel.selected {
            VStack(alignment: .leading, spacing: 4) {
                row("Server", profile.serverName)
                row("Protocol", ThisDeviceTunnelChoices.protocolLabel(profile.protocolID,
                                                                      obfuscated: profile.isObfuscated))
                if tunnel.status.isActive {
                    row("This session", TunnelPresentation.traffic(tunnel.state.statistics))
                    if let handshake = tunnel.state.statistics.lastHandshake {
                        row("Last handshake", TunnelPresentation.age(of: handshake))
                    }
                }
                row("This month", TunnelPresentation.traffic(tunnel.trafficThisMonth()))
            }
            .padding(.bottom, 10)
        }
        if let reason = tunnel.status.failureReason.map(VPNText.failureReason) ?? tunnel.errorMessage {
            Label(reason, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.callout)
    }

    private var connectButton: some View {
        Button {
            Task { await tunnel.toggle() }
        } label: {
            Text(tunnel.status.isActive || tunnel.status == .connecting
                 ? "Disconnect" : "Connect")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .prominentActionButtonStyle()
        .tint(tunnel.status.isActive ? .red : .accentColor)
        .disabled(tunnel.selected == nil || tunnel.status.isBusy)
        .padding(.bottom, 8)
    }

    private var currentPair: ThisDeviceTunnelChoices.Pair? {
        guard let profile = tunnel.active ?? tunnel.selected else { return nil }
        return pairs.first { $0.deployment.id == profile.serverID && $0.protocolID == profile.protocolID }
    }

    private var picker: some View {
        WrappingPicker("Tunnel", selection: Binding<ThisDeviceTunnelChoices.Pair?>(
            get: { currentPair ?? pairs.first },
            set: { pair in
                guard let pair else { return }
                Task { await tunnel.useAsThisDevice(deployment: pair.deployment, protocolID: pair.protocolID) }
            })) {
            ForEach(pairs, id: \.self) { pair in
                Text(verbatim: "\(pair.protocolID.displayName) — \(pair.deployment.name)")
                    .tag(Optional(pair))
            }
        }
        .labelsHidden()
        .disabled(tunnel.status.isBusy || tunnel.isProvisioningThisDevice)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TunnelPresentation.noProfilesNotice)
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Open gryonixNexus") { activate(.app) }
                .buttonStyle(.link)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if tunnel.isDemonstration { DemonstrationNotice(compact: true) }
            HStack {
                Button("Connection") { activate(.tunnel) }
                    .buttonStyle(.link)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.link)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    /// Brings the window forward and points it somewhere
    private func activate(_ destination: AppLink.Destination) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openURL(AppLink.url(for: destination))
    }
}
#endif
