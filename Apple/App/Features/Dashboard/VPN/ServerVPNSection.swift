import AgentControl
import ServerControl
import ServiceCatalog
import SwiftUI

struct ServerVPNSection: View {
    @ObservedObject var viewModel: DashboardViewModel

    /// Which protocol is being shown
    @Binding var selection: ServiceID?
    @State private var showAdd = false
    @State private var pendingName: String?
    @State private var pendingSite: String?
    @State private var pendingDNS: [String] = []
    @State private var comparingDNS = false
    @State private var configuration: VPNShownConfiguration?
    @State private var wantedDNS: [String]?
    /// The ⓘ sheet
    @State private var shownInfo: VPNProtocolInfo?

    private var protocols: [ServiceID] { viewModel.vpnClientProtocols }

    private var selected: ServiceID { viewModel.vpnProtocol(preferring: selection) }

    private var selectedBinding: Binding<ServiceID> {
        Binding(get: { selected }, set: { selection = $0 })
    }

    var body: some View {
        if viewModel.managesVPNClients {
            devices
        } else {
            VPNPanelOnlySection(viewModel: viewModel)
        }
    }

    @ViewBuilder private var devices: some View {
        protocolPickerSection

        ServerThisDeviceSection(deployment: viewModel.deployment, protocolID: selected)

        dnsSection

        if selected == .xrayReality {
            RealityKeySection(viewModel: viewModel)
        }

        VPNDNSPrioritySection(viewModel: viewModel)

        if viewModel.offersVPNMove {
            VPNPlacementSection(viewModel: viewModel)
        }

        Section {
            VPNDeviceRows(viewModel: viewModel, selected: selected,
                          onShowConfiguration: show(_:),
                          onRemove: { device in
                              Task { await viewModel.removeVPNClient(protocol: selected, clientID: device.id) }
                          })
            Button {
                if LicensePrompt.shared.allow() { showAdd = true }
            } label: {
                Label("Add device", systemImage: "plus.circle")
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .task(id: selected) { await viewModel.loadVPNClients(protocol: selected) }
            #if DEBUG
            .task {
                let environment = ProcessInfo.processInfo.environment
                if let raw = environment["GRYONIXNEXUS_DEMO_VPN_PROTOCOL"] { selection = ServiceID(rawValue: raw) }
                if environment["GRYONIXNEXUS_DEMO_VPN_ADD"] != nil {
                    try? await Task.sleep(for: .milliseconds(1500))
                    showAdd = true
                }
            }
            #endif
            .sheet(isPresented: $showAdd, onDismiss: {
                guard let name = pendingName else { return }
                let site = pendingSite
                let dns = pendingDNS
                pendingName = nil
                pendingSite = nil
                Task {
                    if let site { await viewModel.changeRealitySite(to: site) }
                    await viewModel.addVPNClient(protocol: selected, named: name, dns: dns)
                }
            }) {
                VPNClientNameSheet(currentSite: selected == .xrayReality
                                       ? viewModel.deployment.serviceSettings.xrayRealitySNI : nil,
                                   protocolID: selected,
                                   defaultDNS: viewModel.vpnDefaultDNS,
                                   localDNS: LocalDNS(viewModel.vpnDNS),
                                   onCancel: { showAdd = false },
                                   onConfirm: { name, site, dns in
                                       pendingName = name
                                       pendingSite = site
                                       pendingDNS = dns
                                       showAdd = false
                                   })
            }
            .sheet(item: $shownInfo) { info in
                VPNProtocolInfoView(info: info)
            }
            .sheet(item: $configuration) { shown in
                VPNClientConfigSheet(device: shown.device,
                                     configuration: shown.value,
                                     serverID: viewModel.deployment.id,
                                     serverName: viewModel.deployment.name,
                                     protocolID: selected,
                                     localDNS: LocalDNS(viewModel.vpnDNS),
                                     onChangeDNS: { dns in changeDNS(of: shown.device, to: dns) }) {
                    configuration = nil
                }
            }
        } header: {
            HStack {
                if protocols.count > 1 {
                    Text("Devices")
                } else {
                    Text(verbatim: ServiceRegistry.service(selected)?.displayName ?? selected.rawValue)
                }
                Spacer()
                InfoNote("Devices", "Adding a device generates its keys on the server. Open a device to get its configuration — import it into the protocol's app, or scan the code with the phone that will use it.")
            }
        }
    }

    @ViewBuilder
    private var protocolPickerSection: some View {
        if protocols.count > 1 {
            Section {
                WrappingPicker("Protocol", selection: selectedBinding) {
                    ForEach(protocols, id: \.self) { id in
                        Text(verbatim: ServiceRegistry.service(id)?.displayName ?? id.rawValue).tag(id)
                    }
                }
                .pickerStyle(.menu)
                if let info = VPNProtocolInfo.info(for: selected) {
                    Button {
                        shownInfo = info
                    } label: {
                        Label("About \(ServiceRegistry.service(selected)?.displayName ?? selected.rawValue)",
                              systemImage: "info.circle")
                    }
                    .rowActionButtonStyle()
                }
            } header: {
                InfoSectionHeader("Protocol", note: "Each protocol keeps its own devices. A phone added here appears in the VPN panel too — this is the same list, managed from the app.")
            }
        }
    }

    private var dnsSection: some View {
        Section {
            VPNDNSMenu(title: "DNS", addresses: viewModel.vpnDefaultDNS, local: LocalDNS(viewModel.vpnDNS)) { dns in
                Task { await viewModel.setVPNDefaultDNS(dns) }
            }
            Button {
                comparingDNS = true
            } label: {
                Label("Compare public DNS", systemImage: "info.circle")
            }
            .rowActionButtonStyle()
        } header: {
            InfoSectionHeader("DNS", note: "The DNS new devices get. Each device can have its own: choose it when you add one, or open the device to change it.")
        } footer: {
            if LocalDNS(viewModel.vpnDNS).isGone(viewModel.vpnDefaultDNS) {
                VPNDNSFootnote(protocolID: selected, resolverGone: true)
            }
        }
        .task {
            await viewModel.loadVPNDefaultDNS()
            await viewModel.loadVPNDNSPriority()
        }
        .sheet(isPresented: $comparingDNS) {
            PublicDNSInfoView(highlighted: PublicDNS.matching(viewModel.vpnDefaultDNS))
        }
    }

    /// Shows the pick at once, applies picks in turn
    private func changeDNS(of device: VPNClientDevice, to dns: [String]) {
        if let shown = configuration {
            let picked = VPNClientDevice(id: device.id, name: device.name, detail: device.detail, dns: dns)
            configuration = VPNShownConfiguration(device: picked, value: shown.value)
        }
        let idle = wantedDNS == nil
        wantedDNS = dns
        guard idle else { return }
        Task { await applyWantedDNS(of: device) }
    }

    private func applyWantedDNS(of device: VPNClientDevice) async {
        var applied: [String]?
        while let wanted = wantedDNS, wanted != applied {
            await viewModel.setVPNClientDNS(protocol: selected, clientID: device.id, dns: wanted)
            applied = wanted
        }
        wantedDNS = nil
        let updated = viewModel.vpnClients.value?.first { $0.id == device.id } ?? device
        guard configuration?.id == device.id,
              let value = await viewModel.vpnClientConfiguration(protocol: selected, clientID: device.id),
              configuration?.id == device.id else { return }
        configuration = VPNShownConfiguration(device: updated, value: value)
    }

    private func show(_ device: VPNClientDevice) {
        guard LicensePrompt.shared.allow() else { return }
        Task {
            if let value = await viewModel.vpnClientConfiguration(protocol: selected,
                                                                  clientID: device.id) {
                configuration = VPNShownConfiguration(device: device, value: value)
            }
        }
    }
}
