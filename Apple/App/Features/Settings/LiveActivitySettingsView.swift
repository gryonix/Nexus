#if os(iOS)
import SwiftUI

/// What the Dynamic Island and Live Activities show
struct LiveActivitySettingsView: View {
    @ObservedObject private var settings = LiveActivitySettings.shared
    #if DEBUG
    @State private var checkDriver: IslandCheck.Driver?
    #endif

    var body: some View {
        Form {
            operationsSection
            vpnSection
            #if DEBUG
            checkSection
            #endif
        }
        .bottomBarClearance()
        .navigationTitle("Live Activity & Dynamic Island")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var operationsSection: some View {
        Section {
            Toggle("Show running operations", isOn: $settings.showsOperations)
            if settings.showsOperations {
                ForEach(OperationKind.allCases, id: \.self) { kind in
                    Toggle(kind.settingsTitle, isOn: shown(kind))
                }
            }
        } header: {
            Text("Server operations")
        } footer: {
            Text("The server starts these cards itself, also when the app is closed and when the operation was started on another device or by a schedule.")
        }
    }

    private var vpnSection: some View {
        Section {
            VPNLiveActivityRows()
        } header: {
            Text("VPN")
        } footer: {
            Text(VPNLiveActivityRows.note)
        }
    }

    #if DEBUG
    private var checkSection: some View {
        Section {
            Button("Show a test card") {
                Task { if let driver = await IslandCheck.run() { checkDriver = driver } }
            }
        } header: {
            Text("Check")
        } footer: {
            checkFooter
        }
    }

    @ViewBuilder
    private var checkFooter: some View {
        switch checkDriver {
        case .server(let name):
            Text(UIL10n.string("%@ moves the card through the relay. Close the app or lock the phone: it keeps moving and opens wide at the end.", name))
        case .app:
            Text("No server sends notifications through a relay, so the app moves the card. Closing the app stops it.")
        case nil:
            Text("The card runs for 30 seconds. Leave the app or lock the phone to watch it on the island.")
        }
    }
    #endif

    private func shown(_ kind: OperationKind) -> Binding<Bool> {
        Binding(
            get: { !settings.hiddenOperationKinds.contains(kind) },
            set: { on in
                if on { settings.hiddenOperationKinds.remove(kind) } else { settings.hiddenOperationKinds.insert(kind) }
            })
    }
}

extension OperationKind {
    /// The switch label of this kind
    var settingsTitle: LocalizedStringKey {
        switch self {
        case .install: return "Installs"
        case .update: return "Updates"
        case .backup: return "Backups"
        case .restore: return "Restores"
        case .move: return "Moves between machines"
        case .removal: return "Removals"
        case .other: return "Other operations"
        }
    }
}
#endif
