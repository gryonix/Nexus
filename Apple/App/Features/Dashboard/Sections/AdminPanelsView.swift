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

    var body: some View {
        Form {
            guardSection
            pagesSection
        }
        .navigationTitle("Restrict admin panels")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .refreshableWithShortcut { await viewModel.refreshAdminLockdown() }
        .task { await viewModel.refreshAdminLockdownIfStale() }
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
