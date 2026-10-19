import ServerControl
import ServiceCatalog
import SwiftUI

/// Confirms removing one service from the server
struct UninstallServiceSheet: View {
    let service: any ManagedService
    let alsoRemoved: [String]
    let unguardedPanels: [String]
    let onCancel: () -> Void
    let onConfirm: (_ purge: PurgeOptions) -> Void

    /// Two independent choices: the service's data, and its backups
    @State private var purgeData = false
    @State private var purgeBackups = false
    @State private var confirmingPurge = false

    private var purge: PurgeOptions { PurgeOptions(data: purgeData, backups: purgeBackups) }

    var body: some View {
        NavigationStack {
            Form {
                if !alsoRemoved.isEmpty {
                    Section {
                        Label("The VPN services share one panel, so they are removed together: \(alsoRemoved.joined(separator: ", ")).",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }

                if !unguardedPanels.isEmpty {
                    Section {
                        Label("VPN-only access ends with the VPN: these admin panels become reachable from the internet again — \(unguardedPanels.joined(separator: ", ")). Set a strong password on each before removing.",
                              systemImage: "lock.open.trianglebadge.exclamationmark")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }

                Section {
                    Toggle("Delete service data", isOn: $purgeData)
                    Toggle("Delete backups", isOn: $purgeBackups)
                } footer: {
                    Text(purge.isEmpty
                         ? UIL10n.string("Containers and configuration are removed; data and backups stay on disk, so installing the service again can pick them up.")
                         : purgeWarning)
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle("Remove \(service.displayName)?")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Remove", role: .destructive) {
                        if purge.isEmpty {
                            onConfirm(.none)
                        } else {
                            confirmingPurge = true
                        }
                    }
                    .dangerTint()
                }
            }
            .alert("Delete permanently?", isPresented: $confirmingPurge) {
                Button("Delete everything", role: .destructive) { onConfirm(purge) }
                .dangerTint()
                Button("Cancel", role: .cancel) { confirmingPurge = false }
            } message: {
                Text(purgeWarning)
            }
        }
    }

    /// Spells out exactly what disappears, tuned to the two toggles
    private var purgeWarning: String {
        if purgeData && purgeBackups {
            return UIL10n.string("The service's data and every backup of it are deleted permanently. There is no way back from this.")
        }
        if purgeData {
            return UIL10n.string("The service's data is deleted permanently. Its backups stay on disk. This cannot be undone.")
        }
        return UIL10n.string("Every backup of the service is deleted permanently. Its live data stays. This cannot be undone.")
    }
}
