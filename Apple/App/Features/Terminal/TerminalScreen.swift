import ServerControl
import ServerControlSSH
import SwiftUI
import VPNTunnel

/// A live shell, full screen
@available(macOS 15.0, *)
struct TerminalScreen: View {
    let deployment: Deployment
    let profile: TerminalProfile

    @ObservedObject private var controller: TerminalController
    @ObservedObject private var tunnelMark = TunnelStatusMark.shared
    @ObservedObject private var looks = TerminalAppearanceStore.shared
    @ObservedObject private var keys = TerminalAccessoryModel.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var designing = false
    @State private var shakes = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turningOnVPN = false

    init(deployment: Deployment, profile: TerminalProfile) {
        self.deployment = deployment
        self.profile = profile
        controller = TerminalSessions.shared.controller(for: profile, on: deployment)
    }

    var body: some View {
        ZStack {
            backdrop
            TerminalHostView(controller: controller, look: looks.appearance, theme: theme,
                             accessory: keys.layout,
                             zoomTo: { size in looks.update { $0.fontSize = size.rounded() } })
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            stateOverlay
        }
        .screenTitle(Text(verbatim: "\(profile.username)@\(deployment.name)"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: controller.state) { _, state in
            guard case .closed(let reason) = state, reason != nil, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.45)) { shakes += 1 }
        }
        .sheet(isPresented: $designing) {
            NavigationStack { TerminalDesignView(serverID: deployment.id) }
        }
        .toolbar { terminalToolbar }
        // The emulator and its keyboard accessory own the bottom edge.
        .ownsBottomEdge()
        .task {
            #if DEBUG
            if let canned = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_TERMINAL"] {
                controller.feedDebug(canned)
                return
            }
            #endif
            if controller.state == .idle { await start() }
        }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch controller.state {
        case .connecting:
            banner {
                HStack(spacing: 8) {
                    TerminalPulseDot()
                    Text("Connecting…")
                }
            }
        case .reconnecting(let attempt):
            banner {
                HStack(spacing: 8) {
                    TerminalPulseDot()
                    Text("Connection lost. Reconnecting (\(attempt))…")
                }
            }
        case .closed(let reason):
            banner {
                VStack(alignment: .leading, spacing: 6) {
                    Text(reason == nil ? "The session ended." : "The session was disconnected.")
                    if let reason {
                        Text(verbatim: reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    HStack(spacing: 8) {
                        Button("Reconnect") { Task { await start() } }
                            .secondaryActionButtonStyle()
                        if reason != nil, let offer = vpnOffer {
                            Button("Turn on VPN and reconnect") {
                                Task { await connectVPN(offer) }
                            }
                            .secondaryActionButtonStyle()
                            .disabled(turningOnVPN)
                        }
                    }
                }
            }
            .modifier(TerminalShake(steps: CGFloat(shakes)))
        case .live:
            if let route = controller.route, route != .direct {
                routeBadge(route)
            }
        case .idle:
            EmptyView()
        }
    }

    @ToolbarContentBuilder
    private var terminalToolbar: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            AITerminalMenu(controller: controller, serverName: deployment.name)
        }
        ToolbarItem(placement: .secondaryAction) {
            Button { designing = true } label: {
                Label("Terminal design", systemImage: "paintpalette")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button(role: .destructive) {
                TerminalSessions.shared.end(profile)
                dismiss()
            } label: {
                Label("Disconnect", systemImage: "xmark.circle")
            }
            .tint(.red)
            .toolbarGlassButtonStyle()
        }
    }

    private var theme: TerminalTheme {
        looks.appearance.theme(isDark: colorScheme == .dark, server: deployment.id.uuidString)
    }

    @ViewBuilder
    private var backdrop: some View {
        let look = looks.appearance
        if look.opacity < 1, look.blur {
            Rectangle().fill(.ultraThinMaterial)
        } else if look.opacity < 1 {
            Color.clear
        } else {
            Color(theme.color(theme.background))
        }
    }

    @ViewBuilder
    private func banner<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack {
            Spacer()
            content()
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding()
        }
    }

    private func start() async {
        routes = await controller.startResolved()
    }

    @State private var routes: [TerminalEndpoint] = []

    private var tunnel: TunnelController { .shared }

    /// A tunnel worth turning on when no route answered
    private var vpnOffer: TunnelProfile? {
        guard controller.noRouteAnswered, !tunnelMark.status.isActive, !tunnelMark.status.isBusy else { return nil }
        if let own = tunnel.profiles.first(where: { $0.serverID == deployment.id }) { return own }
        let privateOnly = !routes.isEmpty && routes.allSatisfy { TerminalVPNOffer.isPrivate($0.host) }
        return privateOnly ? tunnel.selected : nil
    }

    private func connectVPN(_ profile: TunnelProfile) async {
        turningOnVPN = true
        defer { turningOnVPN = false }
        await tunnel.connect(profile)
        let deadline = ContinuousClock.now.advanced(by: .seconds(25))
        while !tunnel.status.isActive, tunnel.errorMessage == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(300))
        }
        guard tunnel.status.isActive else {
            controller.reportFailure(tunnel.errorMessage ?? UIL10n.string("The VPN did not connect."))
            return
        }
        await start()
    }

    private func routeBadge(_ route: TerminalEndpoint.Kind) -> some View {
        VStack {
            HStack {
                Spacer()
                Label(TerminalVPNOffer.title(of: route), systemImage: TerminalVPNOffer.symbol(of: route))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .padding(8)
            }
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

/// Words and rules for the routes a terminal takes
enum TerminalVPNOffer {
    static func title(of route: TerminalEndpoint.Kind) -> String {
        switch route {
        case .direct: return UIL10n.string("Direct")
        case .localNetwork: return UIL10n.string("Local network")
        case .relay: return UIL10n.string("Through the relay")
        case .tunnelAddress: return UIL10n.string("Through the VPN")
        case .fallbackAddress: return UIL10n.string("Fallback address")
        }
    }

    static func symbol(of route: TerminalEndpoint.Kind) -> String {
        switch route {
        case .direct: return "arrow.right"
        case .localNetwork: return "house"
        case .relay: return "point.3.connected.trianglepath.dotted"
        case .tunnelAddress: return "lock.shield"
        case .fallbackAddress: return "arrow.triangle.branch"
        }
    }

    /// Addresses only a tunnel or the home network reaches
    static func isPrivate(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4 {
            switch (parts[0], parts[1]) {
            case (10, _), (192, 168), (169, 254): return true
            case (172, 16...31), (100, 64...127): return true
            default: return false
            }
        }
        let lower = host.lowercased()
        let uniqueLocal = lower.contains(":") && (lower.hasPrefix("fd") || lower.hasPrefix("fc"))
        return uniqueLocal || lower.hasSuffix(".local")
    }
}
