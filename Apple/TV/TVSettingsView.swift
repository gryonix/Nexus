import SwiftUI
import TVLink

/// The TV's settings: tabs, card style, iCloud, license and phones
struct TVSettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                TVTabsSection()
                TVCardStyleSection()
                TVCloudSection()
                TVLicenceSection()
                Section {
                    LabeledContent("Version", value: Self.version)
                }
            }
            .screenTitle("Settings")
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}

/// Order, visibility and labels of the tabs
private struct TVTabsSection: View {
    @ObservedObject private var tabs = TVTabSettings.shared

    var body: some View {
        Section {
            ForEach(tabs.order) { tab in
                TVTabRow(tab: tab)
            }
        } header: {
            Text("Tabs")
        } footer: {
            Text("Settings is always shown.")
        }
        Section {
            ForEach(tabs.order) { tab in
                TVTabOrderRow(tab: tab)
            }
        } header: {
            Text("Order")
        }
    }
}

/// One tab: shown or hidden, and moved left or right
private struct TVTabRow: View {
    let tab: TVTab
    @ObservedObject private var tabs = TVTabSettings.shared

    var body: some View {
        Toggle(isOn: Binding(get: { !tabs.hidden.contains(tab) },
                             set: { tabs.setVisible($0, for: tab) })) {
            Label(tab.appTab.title, systemImage: tab.appTab.systemImage)
        }
    }
}

/// Moves one tab; the remote reaches one control per row
private struct TVTabOrderRow: View {
    let tab: TVTab
    @ObservedObject private var tabs = TVTabSettings.shared

    var body: some View {
        Menu {
            Button { tabs.move(tab, by: -1) } label: { Label("Move left", systemImage: "arrow.left") }
                .disabled(tabs.order.first == tab)
            Button { tabs.move(tab, by: 1) } label: { Label("Move right", systemImage: "arrow.right") }
                .disabled(tabs.order.last == tab)
        } label: {
            Label(tab.appTab.title, systemImage: tab.appTab.systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// How the server cards look, as on the phone
private struct TVCardStyleSection: View {
    var body: some View {
        Section {
            NavigationLink {
                AppearanceCardsView()
            } label: {
                Label("Server cards", systemImage: "rectangle.grid.1x2")
            }
        }
    }
}

private struct TVCloudSection: View {
    @ObservedObject private var sync = CloudSync.shared

    var body: some View {
        Section {
            LabeledContent("iCloud sync", value: statusText)
            Button("Sync now") { Task { await sync.sync() } }
        } header: {
            Text("iCloud")
        } footer: {
            Text(note)
        }
    }

    private var statusText: String {
        switch sync.status {
        case .idle: return UIL10n.string("On")
        case .syncing: return UIL10n.string("Syncing…")
        case .needsPassword: return UIL10n.string("Needs the password")
        case .failed(let message): return message
        case .synced(let date): return date.formatted(date: .omitted, time: .shortened)
        }
    }

    private var note: LocalizedStringKey {
        sync.status == .needsPassword
            ? "Your servers in iCloud are locked with a password, and nothing is typed on this Apple TV. Send servers from your iPhone instead: Settings › Apple TV."
            : "Servers and their keys come from your other devices. Deleting a server here removes it from this Apple TV only."
    }
}

/// The license and the phones that confirm it
private struct TVLicenceSection: View {
    @ObservedObject private var license = LicenseStore.shared
    @ObservedObject private var link = TVLinkHostModel.shared
    @State private var pairing = false
    @State private var forgetting: TVPairedPhone?

    var body: some View {
        Section {
            LabeledContent("License", value: license.status.isActive ? UIL10n.string("Active") : UIL10n.string("Not confirmed"))
            if let end = link.licenceEnds {
                LabeledContent("Confirmed until", value: end.formatted(date: .abbreviated, time: .shortened))
            }
            ForEach(link.phones) { phone in
                Button { forgetting = phone } label: {
                    LabeledContent(phone.name, value: phone.lastSeen.formatted(.relative(presentation: .named)))
                }
            }
            Button("Pair an iPhone") { pairing = true }
        } header: {
            Text("License and iPhone")
        } footer: {
            Text("A paired iPhone confirms the license whenever Nexus is open on it nearby. Without it this Apple TV stays unlocked for 10 days, or 20 with a lifetime license.")
        }
        .sheet(isPresented: $pairing) { TVPhonePairingSheet() }
        .confirmationDialog("Forget this iPhone?", isPresented: $forgetting.isPresent(),
                            presenting: forgetting) { phone in
            Button("Forget", role: .destructive) { link.forget(phone) }
            Button("Cancel", role: .cancel) {}
        }
    }
}
