import ServerControl
import ServiceCatalog
import SwiftUI

/// The panel guard as one Security row
struct AdminLockdownRow: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var route: SecurityRoute?

    var body: some View {
        SecurityRow(title: "Restrict admin panels", systemImage: "lock.shield",
                    tint: isActive ? .green : .secondary,
                    caption: "WireGuard only",
                    status: isUnread ? "Could not read" : nil,
                    refreshLabel: "Read the panel guard again",
                    isRefreshing: viewModel.adminLockdown.isLoading,
                    refresh: { await viewModel.refreshAdminLockdown() },
                    open: { route = .adminPanels }) {
            master
        }
        .task { await viewModel.refreshAdminLockdownIfStale() }
    }

    private var isActive: Bool { viewModel.adminLockdown.value?.isActive ?? false }

    private var isUnread: Bool { viewModel.adminLockdown.errorMessage != nil }

    @ViewBuilder private var master: some View {
        if let state = viewModel.adminLockdown.value {
            SecuritySwitch(isOn: state.isActive) { wanted in
                Task { await viewModel.setAdminLockdown(wanted) }
            }
        }
    }
}

/// Which admin panels answer over the tunnel only
struct AdminPanelsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var apiService: ServiceID?

    var body: some View {
        Form {
            guardSection
            if !apiServices.isEmpty {
                AllOpenAPISection(model: viewModel.openAPI, services: apiServices)
            }
            pagesSection
        }
        .screenTitle("Restrict admin panels")
        #if os(iOS) || os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(item: $apiService) { id in
            ServiceOpenAPIView(viewModel: viewModel, model: viewModel.openAPI, service: id,
                               name: ServiceRegistry.service(id)?.displayName ?? id.rawValue)
        }
        .refreshableWithShortcut {
            await viewModel.refreshAdminLockdown()
            await viewModel.openAPI.refresh()
        }
        .task {
            await viewModel.refreshAdminLockdownIfStale()
            if !apiServices.isEmpty { await viewModel.openAPI.refresh() }
        }
    }

    /// Services whose apps can be let past the VPN
    private var apiServices: [ServiceID] {
        viewModel.offersOpenAPI ? OpenAPIModel.services(in: viewModel.deployment) : []
    }

    @ViewBuilder private var guardSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { viewModel.adminLockdown.value?.isActive ?? false },
                set: { wanted in Task { await viewModel.setAdminLockdown(wanted) } }
            )) {
                Label("WireGuard only", systemImage: "lock.shield")
            }
            .disabled(viewModel.adminLockdown.value == nil)
        } header: {
            InfoSectionHeader("Restrict admin panels",
                              isRefreshing: viewModel.adminLockdown.isLoading,
                              refresh: { await viewModel.refreshAdminLockdown() }) {
                Text("With this on, the admin panels answer only over the VPN; mail, user services and SSH stay public. WireGuard and AmneziaWG clients of the VPN panel reach them; Shadowsocks and XRay carry internet traffic but never reach the panels — their traffic to the server's own address leaves the tunnel. Create yourself a WireGuard client in the VPN panel and test it before switching this on.")
            }
        } footer: {
            if let message = viewModel.adminLockdown.errorMessage {
                Text(verbatim: message)
            }
        }
    }

    @ViewBuilder private var pagesSection: some View {
        Section("Panels") {
            ForEach(viewModel.lockdownPages, id: \.host) { page in
                pageRow(page)
            }
        }
    }

    private func pageRow(_ page: (id: ServiceID, name: String, host: String)) -> some View {
        HStack(spacing: 10) {
            pageToggle(page)
            if apiServices.contains(page.id) {
                Button { apiService = page.id } label: {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Access without the VPN"))
            }
        }
    }

    private func pageToggle(_ page: (id: ServiceID, name: String, host: String)) -> some View {
        Toggle(isOn: Binding(
            get: { viewModel.adminLockdown.value?.guards(page.host) ?? false },
            set: { wanted in Task { await viewModel.setLockdown(host: page.host, guarded: wanted) } }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: page.name)
                Text(verbatim: page.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .disabled(viewModel.adminLockdown.value == nil)
    }
}

/// One switch for every service's app APIs
struct AllOpenAPISection: View {
    @ObservedObject var model: OpenAPIModel
    let services: [ServiceID]

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { model.allOpen(services: services) == true },
                set: { wanted in Task { await model.setAll(open: wanted, services: services) } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("App APIs without the VPN", systemImage: "app.connected.to.app.below.fill")
                    if model.allOpen(services: services) == nil, model.sites.value != nil {
                        Text("Some are open — the arrow next to a service shows which.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(model.sites.value == nil || !model.busy.isEmpty)
        } header: {
            InfoSectionHeader("App APIs", isRefreshing: model.sites.isLoading || !model.busy.isEmpty,
                              refresh: { await model.refresh() }) {
                Text("Apps such as Bitwarden, mail and photo backup reach their server without the VPN, and still sign in with their own password. The pages and admin of each site stay behind the VPN.")
            }
        } footer: {
            if let message = model.failure ?? model.sites.errorMessage {
                Text(verbatim: message)
            }
        }
    }
}
