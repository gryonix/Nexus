import ServerControl
import ServiceCatalog
import SwiftUI

/// One place for a machine's system-level settings
struct SystemPage: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject private var modules = ModuleSettings.shared
    @State private var rebootTarget: SSHHostID?
    #if !os(tvOS)
    @StateObject private var settings: SystemSettingsModel
    @StateObject private var updates: SystemUpdateModel
    @StateObject private var edits = PendingRowEdits()

    init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
        _settings = StateObject(wrappedValue: SystemSettingsModel.make(for: viewModel))
        _updates = StateObject(wrappedValue: SystemUpdateModel.make(for: viewModel))
    }

    private var hosts: [SSHHostID] { viewModel.deployment.nodes.map(\.sshHost) }
    #endif

    var body: some View {
        CardList {
            Section {
                NavigationLink {
                    SystemUpdatePage(viewModel: viewModel)
                } label: {
                    Label("System update", systemImage: "shippingbox")
                }
                #if !os(tvOS)
                NavigationLink {
                    SystemSwapPage(viewModel: viewModel)
                } label: {
                    Label("Swap", systemImage: "memorychip")
                }
                #endif
            }
            #if !os(tvOS)
            if modules.isOn(.portForwarding, server: viewModel.deployment.id.uuidString) {
                Section {
                    NavigationLink {
                        PortForwardsView(deployment: viewModel.deployment)
                    } label: {
                        Label("Port forwarding", systemImage: "arrow.left.arrow.right")
                    }
                }
            }
            ForEach(hosts, id: \.self) { host in
                if settings.settings[host] != nil || updates.statuses[host]?.rebootSchedule != nil {
                    Section {
                        SystemSettingsRows(model: settings, host: host)
                        RebootScheduleRows(model: updates, host: host, edits: edits)
                    } header: {
                        if hosts.count > 1, let label = viewModel.deployment.metricsMachineLabel(for: host) {
                            Text(verbatim: label)
                        }
                    }
                }
            }
            #endif
            Section {
                ForEach(viewModel.deployment.nodes, id: \.id) { node in
                    Button(role: .destructive) {
                        rebootTarget = node.sshHost
                    } label: {
                        Label(DashboardViewModel.rebootTitle(for: node, in: viewModel.deployment),
                              systemImage: "power")
                    }
                    .dangerTint()
                }
            }
        }
        .screenTitle(Text("System"))
        .raisedNavigationTitle()
        #if !os(tvOS)
        .task {
            await settings.load(hosts)
            await updates.load(hosts)
        }
        .pendingRowEdits(edits)
        #endif
        .alert("Reboot this machine?", isPresented: Binding(get: { rebootTarget != nil },
                                                           set: { if !$0 { rebootTarget = nil } })) {
            Button("Reboot", role: .destructive) {
                if let target = rebootTarget { Task { await viewModel.rebootHost(target) } }
                rebootTarget = nil
            }
            .dangerTint()
            Button("Cancel", role: .cancel) { rebootTarget = nil }
        } message: {
            Text("The machine will go offline for about a minute while it restarts.")
        }
    }
}

#if !os(tvOS)
/// The swap of each machine
struct SystemSwapPage: View {
    @ObservedObject var viewModel: DashboardViewModel
    @StateObject private var model: SystemUpdateModel
    @StateObject private var edits = PendingRowEdits()

    init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
        _model = StateObject(wrappedValue: SystemUpdateModel.make(for: viewModel))
    }

    private var hosts: [SSHHostID] { viewModel.deployment.nodes.map(\.sshHost) }

    var body: some View {
        CardList {
            ForEach(hosts, id: \.self) { host in
                Section {
                    SwapControl(model: model, host: host, status: model.statuses[host], edits: edits)
                    if let error = model.errors[host] {
                        Text(verbatim: error).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    if let label = viewModel.deployment.metricsMachineLabel(for: host) {
                        Text(verbatim: label)
                    }
                }
            }
        }
        .screenTitle(Text("Swap"))
        .raisedNavigationTitle()
        .pendingRowEdits(edits)
        .task { await model.load(hosts) }
    }
}
#endif
