import ServiceCatalog
import SwiftUI

/// Quick links to the installed services' web UIs
struct SitesSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject private var tabs = TabBarSettings.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        let sites = viewModel.webSites
        if sites.isEmpty, viewModel.sitesNeedDomain {
            Section {
                Label("This server has no domain set, so its addresses cannot be built.",
                      systemImage: "questionmark.circle")
                    .font(.callout)
            } header: {
                Text("Sites")
            } footer: {
                Text("Set it in Connection Settings — the “…” menu at the top right. Every service address is the service's name plus that domain.")
            }
        } else if !sites.isEmpty {
            if tabs.sitesCollapsible {
                Section {
                    DisclosureGroup(isExpanded: Binding(
                        get: { tabs.sitesExpanded },
                        set: { newValue in withAnimation(.smooth) { tabs.sitesExpanded = newValue } }
                    )) {
                        ForEach(sites) { site in
                            row(site).appTourTarget(.serverSites)
                            homeDoorRow(site)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Sites")
                            Text(verbatim: "\(sites.count)")
                                .foregroundStyle(.secondary)
                        }
                        .appTourTarget(.serverSites)
                    }
                } footer: {
                    homeNetworkNote(sites)
                }
            } else {
                Section {
                    ForEach(sites) { site in
                        row(site).appTourTarget(.serverSites)
                        homeDoorRow(site)
                    }
                } header: {
                    Text("Sites")
                } footer: {
                    homeNetworkNote(sites)
                }
            }
        }
    }

    /// .local names exist only on the local network
    @ViewBuilder
    private func homeNetworkNote(_ sites: [DashboardViewModel.WebSite]) -> some View {
        if sites.contains(where: { $0.host.lowercased().hasSuffix(".local") }) {
            Text("Opens only from your home network.")
        }
    }

    /// The plain address phone and desktop apps use at home
    @ViewBuilder
    private func homeDoorRow(_ site: DashboardViewModel.WebSite) -> some View {
        if let address = viewModel.homeDoorURL(for: site.id) {
            HomeDoorRow(label: "For apps at home", address: address)
            if let away = viewModel.meshDoorURL(for: site.id) {
                HomeDoorRow(label: "Away from home, through the VPN", address: away)
            }
            UnencryptedDoorNote()
        }
    }

    @ViewBuilder
    private func row(_ site: DashboardViewModel.WebSite) -> some View {
        Button {
            if let url = site.url { openURL(url) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: site.systemImage)
                    .foregroundStyle(.tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: site.name)
                        .foregroundStyle(.primary)
                    Text(verbatim: site.host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(site.url == nil)
        #if os(iOS)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        #endif
    }
}

/// Copies the home-network address for apps
private struct HomeDoorRow: View {
    let label: LocalizedStringKey
    let address: String
    @State private var copied = false

    var body: some View {
        Button {
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(address, forType: .string)
            #else
            UIPasteboard.general.string = address
            #endif
            copied = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "iphone.and.arrow.forward")
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(verbatim: address)
                        .font(.callout.monospaced())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.callout)
                    .foregroundStyle(.tint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Copies the address"))
    }
}

/// Says the plain address carries no encryption
private struct UnencryptedDoorNote: View {
    var body: some View {
        Label {
            Text("Not encrypted: use it only on your home network or through the VPN.")
        } icon: {
            Image(systemName: "lock.open")
        }
        .font(.caption)
        .foregroundStyle(.orange)
    }
}
