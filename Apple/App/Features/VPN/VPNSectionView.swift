import AgentControl
import ServerControl
import ServiceCatalog
import SwiftUI
import VPNTunnel

/// "VPN" — client devices across the whole fleet
struct VPNSectionView: View {
    @StateObject private var servers = ServerListViewModel()
    @State private var path = NavigationPath()
    @ObservedObject private var navigator = AppNavigator.shared
    @ObservedObject private var tunnel = TunnelController.shared

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if manageable.isEmpty && panelOnly.isEmpty && tunnel.profiles.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("VPN")
            .sectionToolbar(.vpn)
            .navigationDestination(for: Deployment.self) { deployment in
                VPNClientsHost(deployment: deployment)
            }
            .onReceive(navigator.$sectionServer.compactMap {
                $0?.tab == .vpn ? $0?.deploymentID : nil
            }) { open($0) }
            .task { if let id = navigator.sectionServer(for: .vpn) { open(id) } }
            .onChange(of: navigator.focusTunnel) { _, wanted in
                if wanted { clearFocusAfterAMoment() }
            }
            .task { if navigator.focusTunnel { clearFocusAfterAMoment() } }
            .task {
                servers.load()
                #if DEBUG
                if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_OPEN_VPN"] != nil,
                   let first = manageable.first {
                    path.append(first)
                }
                #endif
            }
            .refreshableWithShortcut { servers.load() }
        }
        .popToRootOnReselect(.vpn) { path = NavigationPath() }
    }

    /// Pushes one server's devices screen
    private func open(_ deploymentID: UUID) {
        navigator.clearSectionServer(for: .vpn)
        if servers.deployments.isEmpty { servers.load() }
        guard let deployment = manageable.first(where: { $0.id == deploymentID }) else { return }
        path.append(deployment)
    }

    private func clearFocusAfterAMoment() {
        Task {
            try? await Task.sleep(for: .seconds(2))
            navigator.clearTunnelFocus()
        }
    }

    private var list: some View {
        CardList {
            ThisDeviceCard(tunnel: tunnel, highlighted: navigator.focusTunnel)

            if !manageable.isEmpty {
                Section {
                    ForEach(manageable) { deployment in
                        NavigationLink(value: deployment) {
                            row(deployment)
                        }
                    }
                } header: {
                    InfoSectionHeader("Servers", note: "Devices are added on the server and appear in its VPN panel too — this is the same list, managed from the app.")
                }
            }

            OnDemandSection()
            #if os(iOS)
            LiveActivitySection()
            #endif

            if !panelOnly.isEmpty {
                Section {
                    ForEach(panelOnly) { deployment in
                        row(deployment)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    InfoSectionHeader("Managed in the panel") { Text(panelOnlyReason) }
                }
            }
        }
    }

    private func row(_ deployment: Deployment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: deployment.name)
            Text(verbatim: protocolNames(of: deployment))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func protocolNames(of deployment: Deployment) -> String {
        VPNClientProtocols.installed(in: deployment.services)
            .map { ServiceRegistry.service($0)?.displayName ?? $0.rawValue }
            .joined(separator: " · ")
    }

    private var manageable: [Deployment] {
        guard agentTransportAvailable else { return [] }
        return Self.manageable(in: servers.deployments)
    }

    static func manageable(in deployments: [Deployment]) -> [Deployment] {
        deployments.filter {
            !VPNClientProtocols.installed(in: $0.services).isEmpty
                && $0.usesAgent
                && $0.serviceSettings.vpnClientAccess.allowsAppManagement
        }
    }

    /// A VPN, but no route to manage it from here
    private var panelOnly: [Deployment] {
        withVPN.filter { !manageable.contains($0) }
    }

    private var panelOnlyReason: LocalizedStringKey {
        let byChoice = panelOnly.filter { $0.usesAgent && !$0.serviceSettings.vpnClientAccess.allowsAppManagement }
        if byChoice.count == panelOnly.count {
            return "These servers hand out VPN configurations from their own panel — that is how they are set up. Change it in the server's VPN settings to manage devices here as well."
        }
        if byChoice.isEmpty {
            return "These servers run a VPN, but the app cannot manage their devices: that goes through the server's own agent. Install the agent on the server, or open its VPN panel to add a device there."
        }
        return "Some of these hand out configurations from their own panel by choice; the rest have no agent installed for the app to go through."
    }

    private var withVPN: [Deployment] {
        servers.deployments.filter { !VPNClientProtocols.installed(in: $0.services).isEmpty }
    }

    private var agentTransportAvailable: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            AppTab.vpn.icon
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .foregroundStyle(.secondary)
            Text("No VPN yet")
                .font(.title3.weight(.semibold))
            Text("Install a VPN protocol on one of your servers and its devices appear here — add a phone, hand it its configuration, take it away again.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct VPNClientsHost: View {
    @StateObject private var viewModel: DashboardViewModel
    private let initialProtocol: ServiceID?

    init(deployment: Deployment, initialProtocol: ServiceID? = nil) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(deployment: deployment))
        self.initialProtocol = initialProtocol
    }

    var body: some View {
        VPNClientsView(viewModel: viewModel, initialProtocol: initialProtocol)
    }
}

#Preview {
    VPNSectionView()
}

#if os(iOS)
/// The VPN session's Live Activity and its two looks
struct LiveActivitySection: View {
    var body: some View {
        Section {
            VPNLiveActivityRows()
        } header: {
            InfoSectionHeader("Live Activity & Dynamic Island", note: VPNLiveActivityRows.note)
        }
    }
}

/// The session switch and the two looks it opens
struct VPNLiveActivityRows: View {
    @ObservedObject private var settings = LiveActivitySettings.shared

    static let note: LocalizedStringKey = "While the VPN is on, the connection stays on the Lock Screen and in the Dynamic Island. iOS shows both together: each has its own look, but they turn on and off as one."

    var body: some View {
        Toggle("Show while the VPN is on", isOn: $settings.showsVPNSession)
        if settings.showsVPNSession {
            NavigationLink("Lock Screen") { VPNLockScreenSettingsView() }
            NavigationLink("Dynamic Island") { VPNIslandSettingsView() }
        }
    }
}
#endif

struct OnDemandSection: View {
    @ObservedObject private var settings = TunnelOnDemandSettings.shared
    @State private var draftNetwork = ""

    var body: some View {
        Section {
            Toggle("Connect automatically", isOn: $settings.isEnabled)
            if settings.isEnabled {
                scopePicker
                if settings.scope != .cellularOnly { networks }
            }
        } header: {
            InfoSectionHeader("Automatic", note: "The system brings the tunnel up on its own, before anything else connects — including after a restart, without the app being opened.")
        } footer: {
            if settings.isEnabled, settings.scope != .cellularOnly { Text(networksNote) }
        }
    }

    private var scopePicker: some View {
        WrappingPicker("Network", selection: $settings.scope) {
            #if os(macOS)
            Text("Any network").tag(TunnelOnDemandPolicy.Scope.anyNetwork)
            Text("Wi-Fi only").tag(TunnelOnDemandPolicy.Scope.wiFiOnly)
            #else
            Text("Wi-Fi and cellular").tag(TunnelOnDemandPolicy.Scope.anyNetwork)
            Text("Wi-Fi only").tag(TunnelOnDemandPolicy.Scope.wiFiOnly)
            Text("Cellular only").tag(TunnelOnDemandPolicy.Scope.cellularOnly)
            #endif
        }
    }

    private var networksNote: LocalizedStringKey {
        settings.networkMode == .onlyListed
            ? "On Wi-Fi the tunnel comes up only on the networks listed here."
            : "On the networks listed here the tunnel stays down."
    }

    @ViewBuilder private var networks: some View {
        Picker("Wi-Fi networks", selection: $settings.networkMode) {
            Text("Except listed").tag(TunnelOnDemandPolicy.NetworkMode.exceptListed)
            Text("Only listed").tag(TunnelOnDemandPolicy.NetworkMode.onlyListed)
        }
        ForEach(settings.trustedNetworks, id: \.self) { network in
            HStack {
                Label(network, systemImage: "wifi")
                Spacer()
                Button {
                    settings.stopTrusting(network)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Remove this network"))
            }
        }
        HStack {
            TextField("Wi-Fi network name", text: $draftNetwork)
                .onSubmit(addNetwork)
            Button("Add", action: addNetwork)
                .buttonStyle(.borderless)
                .disabled(draftNetwork.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func addNetwork() {
        settings.trust(draftNetwork)
        draftNetwork = ""
    }
}
