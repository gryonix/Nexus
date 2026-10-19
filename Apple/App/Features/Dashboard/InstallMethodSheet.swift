import gryonixNexusCore
import ServiceCatalog
import SwiftUI

/// How the chosen services go onto the server
struct InstallMethodSheet: View {
    /// What the run does to the server
    enum Purpose { case install, repair, reinstall }

    let services: [any ManagedService]
    let scripts: [Artifact]
    var purpose = Purpose.install
    let onDevice: () -> Void
    let onCancel: () -> Void
    @State private var asking: LicenseGate.Reason?

    private var title: Text {
        switch purpose {
        case .install: Text("Install")
        case .repair: Text("Repair")
        case .reinstall: Text("Reinstall")
        }
    }

    private var deviceTitle: Text {
        switch purpose {
        case .install: Text("Install from this device")
        case .repair: Text("Repair from this device")
        case .reinstall: Text("Reinstall from this device")
        }
    }

    var body: some View {
        NavigationStack {
            CardList {
                Section {
                    Button(action: installHere) {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                deviceTitle.font(.headline)
                                Text("The agent installs on the server and keeps going if you close the app.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "bolt.fill").foregroundStyle(.tint)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text(verbatim: services.map(\.displayName).joined(separator: ", "))
                }
                if !scripts.isEmpty {
                    Section {
                        ForEach(scripts) { artifact in
                            NavigationLink {
                                ArtifactDetailView(artifact: artifact)
                            } label: {
                                SimpleArtifactRow(artifact: artifact)
                            }
                        }
                    } header: {
                        Text("Or run the scripts yourself")
                    } footer: {
                        Text("Or run the script yourself on the server — open it to copy or share the file.")
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .licenseAsk($asking)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
    }

    private func installHere() {
        guard LicenseStore.shared.status.isActive else {
            asking = LicenseGate.reason
            return
        }
        onDevice()
    }
}
