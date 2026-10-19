import AgentControl
import ServerControl
import ServiceCatalog
import SwiftUI
import VPNTunnel

/// Each server's devices per protocol, for picking a configuration
@MainActor
final class ServerTunnelClients: ObservableObject {
    @Published private(set) var clients: [String: [VPNClientDevice]] = [:]

    static func key(_ deploymentID: UUID, _ protocolID: ServiceID) -> String {
        "\(deploymentID.uuidString)|\(protocolID.rawValue)"
    }

    func devices(of deployment: Deployment, _ protocolID: ServiceID) -> [VPNClientDevice] {
        clients[Self.key(deployment.id, protocolID)] ?? []
    }

    func load(_ deployments: [Deployment]) async {
        for deployment in deployments {
            let viewModel = DashboardViewModel(deployment: deployment)
            for protocolID in ThisDeviceTunnelChoices.protocols(for: deployment) {
                await load(deployment, protocolID, with: viewModel)
            }
        }
    }

    /// Lists one protocol's devices again
    func reload(_ deployment: Deployment, _ protocolID: ServiceID) async {
        await load(deployment, protocolID, with: DashboardViewModel(deployment: deployment))
    }

    private func load(_ deployment: Deployment, _ protocolID: ServiceID,
                      with viewModel: DashboardViewModel) async {
        await viewModel.loadVPNClients(protocol: protocolID)
        if case .loaded(let devices) = viewModel.vpnClients {
            clients[Self.key(deployment.id, protocolID)] = devices
        }
    }

    /// Each server's own resolver, once it has answered
    @Published private(set) var localDNS: [UUID: LocalDNS] = [:]

    /// The live answer, else the last one this device saw
    func local(of serverID: UUID) -> LocalDNS {
        localDNS[serverID] ?? LocalDNSMemory.recall(serverID) ?? LocalDNS()
    }

    /// Asks a server for its resolver until it offers one
    func loadLocalDNS(of deployment: Deployment) async {
        guard localDNS[deployment.id]?.isOffered != true else { return }
        let viewModel = DashboardViewModel(deployment: deployment)
        await viewModel.loadVPNDefaultDNS()
        guard viewModel.vpnDNS != VPNDNSDefaults() else { return }
        let local = LocalDNS(viewModel.vpnDNS)
        localDNS[deployment.id] = local
        LocalDNSMemory.keep(local, for: deployment.id)
    }
}

/// Server, then protocol, then which configuration this device uses
struct TunnelConfigurationMenu: View {
    @ObservedObject var tunnel: TunnelController
    @ObservedObject var clients: ServerTunnelClients
    let servers: [Deployment]
    let width: CGFloat

    var body: some View {
        Menu {
            ForEach(servers) { deployment in
                Menu(deployment.name) {
                    ForEach(ThisDeviceTunnelChoices.protocols(for: deployment), id: \.self) { protocolID in
                        Menu(ServiceRegistry.service(protocolID)?.displayName ?? protocolID.rawValue) {
                            TunnelConfigurationChoices(tunnel: tunnel, clients: clients,
                                                       deployment: deployment, protocolID: protocolID)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "chevron.down.circle")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: width, height: width)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Choose server and protocol"))
    }
}

/// This device's own configuration, then other devices'
struct TunnelConfigurationChoices: View {
    @ObservedObject var tunnel: TunnelController
    @ObservedObject var clients: ServerTunnelClients
    let deployment: Deployment
    let protocolID: ServiceID

    var body: some View {
        MenuChoice("This device's own", picked: isOwnInUse) {
            Task { await tunnel.useAsThisDevice(deployment: deployment, protocolID: protocolID) }
        }
        if !others.isEmpty {
            Section("Use another device's configuration") {
                ForEach(others) { device in
                    VerbatimMenuChoice(device.name, picked: isInUse(device.id)) {
                        Task { await tunnel.use(device, deployment: deployment, protocolID: protocolID) }
                    }
                }
            }
        }
    }

    private var others: [VPNClientDevice] {
        ThisDeviceTunnelChoices.otherDevices(
            clients.devices(of: deployment, protocolID),
            ownDeviceID: tunnel.ownProfile(serverID: deployment.id, protocolID: protocolID)?.deviceID)
    }

    private var isOwnInUse: Bool {
        guard let own = tunnel.ownProfile(serverID: deployment.id, protocolID: protocolID) else { return false }
        return tunnel.selected?.id == own.id
    }

    private func isInUse(_ deviceID: String) -> Bool {
        guard let chosen = tunnel.selected else { return false }
        return chosen.serverID == deployment.id && chosen.protocolID == protocolID && chosen.deviceID == deviceID
    }
}
