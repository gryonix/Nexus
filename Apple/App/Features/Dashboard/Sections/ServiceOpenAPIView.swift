import AgentControl
import ServerControl
import ServiceCatalog
import SwiftUI

/// One service's APIs, each open or closed without the VPN
struct ServiceOpenAPIView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var model: OpenAPIModel
    let service: ServiceID
    let name: String
    @StateObject private var edits = PendingRowEdits()

    var body: some View {
        Form {
            OpenAPIGroupsSection(model: model, service: service, siteGuarded: siteGuarded, edits: edits)
        }
        .pendingRowEdits(edits)
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .screenTitle(name)
        #if os(iOS) || os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .refreshableWithShortcut { await model.refresh() }
        .task {
            await model.refresh()
            await viewModel.refreshAdminLockdownIfStale()
        }
    }

    /// Whether the guard covers this service's site
    private var siteGuarded: Bool? {
        guard let host = viewModel.lockdownPages.first(where: { $0.id == service })?.host else { return nil }
        return viewModel.adminLockdown.value?.guards(host)
    }
}

/// The switches of one service's API groups
struct OpenAPIGroupsSection: View {
    @ObservedObject var model: OpenAPIModel
    let service: ServiceID
    var siteGuarded: Bool?
    let edits: PendingRowEdits
    @State private var draft: [String: Bool] = [:]

    /// Groups whose switch differs from the server
    private func waiting(_ asked: [String: Bool]) -> [(group: ServiceAPIGroup, open: Bool)] {
        Self.waiting(asked, among: ServiceAPIGroups.groups(for: service)) { model.isOpen($0, of: service) }
    }

    /// The wanted switches that differ, in catalog order
    static func waiting(_ asked: [String: Bool], among groups: [ServiceAPIGroup],
                        isOpen: (ServiceAPIGroup) -> Bool) -> [(group: ServiceAPIGroup, open: Bool)] {
        groups.compactMap { group in
            guard let open = asked[group.id], open != isOpen(group) else { return nil }
            return (group, open)
        }
    }

    /// Tells the bar whether the switches wait
    private func offerEdit() {
        let field = $draft
        let edit = PendingRowEdits.Edit(
            id: "open-api-\(service.rawValue)", text: .apply,
            apply: { [model, service] in
                for change in waiting(field.wrappedValue) {
                    await model.set(change.group, of: service, open: change.open)
                }
                field.wrappedValue = [:]
                return model.failure == nil
            },
            revert: { field.wrappedValue = [:] })
        edits.offer(edit, changed: !waiting(draft).isEmpty)
    }

    var body: some View {
        Section {
            ForEach(ServiceAPIGroups.groups(for: service)) { group in
                Toggle(isOn: Binding(
                    get: { draft[group.id] ?? model.isOpen(group, of: service) },
                    set: { draft[group.id] = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: UIL10n.string(group.title))
                        Text(verbatim: UIL10n.string(group.detail))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!model.canChange(service))
            }
            .onChange(of: draft) { offerEdit() }
        } header: {
            InfoSectionHeader("Without the VPN", isRefreshing: model.sites.isLoading || model.busy.contains(service),
                              refresh: { await model.refresh() }) {
                Text("On: the apps reach these paths from anywhere and still sign in with their own password. The site's pages and admin stay behind the VPN.")
            }
        } footer: {
            if let note { Text(verbatim: note) }
        }
    }

    private var note: String? {
        if let failure = model.failure { return failure }
        if let message = model.sites.errorMessage { return message }
        guard model.sites.value != nil else { return nil }
        guard let site = model.site(service) else {
            return UIL10n.string("This service has no web address on this server.")
        }
        if !site.editable {
            return UIL10n.string("This site was changed by hand, so the app leaves it as it is.")
        }
        if siteGuarded == false {
            return UIL10n.string("The VPN restriction is off for this site, so all of it is open anyway.")
        }
        return nil
    }
}
