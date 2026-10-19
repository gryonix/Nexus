import ServerControl
import SwiftUI

struct EraseServerSheet: View {
    let deployment: Deployment
    let onCancel: () -> Void
    let onConfirm: (PurgeOptions) -> Void

    @State private var purgeData = false
    @State private var purgeBackups = false
    @State private var confirming = false
    @State private var typed = ""
    @State private var unlockDenied = false

    static let confirmationWord = "DELETE"

    private var typedTheWord: Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines) == Self.confirmationWord
    }

    private var purge: PurgeOptions { PurgeOptions(data: purgeData, backups: purgeBackups) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("This removes everything gryonixNexus installed: containers, the reverse proxy, the tunnel, helper scripts and the app's own access — on every machine of this server.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }

                Section {
                    Toggle("Delete all service data", isOn: $purgeData)
                    Toggle("Delete all backups", isOn: $purgeBackups)
                } footer: {
                    Text(purge.isEmpty
                         ? UIL10n.string("Service data and backups stay on disk, so a later reinstall can pick them up.")
                         : warning)
                }

                Section {
                    TextField(String(""), text: $typed, prompt: Text(verbatim: Self.confirmationWord))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                        .font(.body.monospaced())
                } header: {
                    Text("Type \(Self.confirmationWord) to confirm")
                } footer: {
                    Text("Then Face ID, Touch ID or the device passcode is asked for before anything is removed.")
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle("Erase \(deployment.name)?")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Erase server", role: .destructive) { confirming = true }
                    .dangerTint()
                    .disabled(!typedTheWord)
                }
            }
            .alert("Erase this server?", isPresented: $confirming) {
                Button("Erase everything", role: .destructive) { unlockThenErase() }
                .dangerTint()
                Button("Cancel", role: .cancel) { confirming = false }
            } message: {
                Text(purge.isEmpty
                     ? UIL10n.string("gryonixNexus will be removed from every machine of this server. Service data and backups are kept on disk.")
                     : warning)
            }
            .alert("Not unlocked", isPresented: $unlockDenied) {
                Button("OK") { unlockDenied = false }
            } message: {
                Text("Nothing was removed. Unlock with Face ID, Touch ID or the device passcode to erase this server.")
            }
        }
    }

    private func unlockThenErase() {
        let purge = purge
        Task {
            if await BiometricGate.authenticate(
                reason: UIL10n.string("Unlock to erase this server")) {
                onConfirm(purge)
            } else {
                unlockDenied = true
            }
        }
    }

    /// Exactly what disappears, tuned to the two toggles
    private var warning: String {
        if purgeData && purgeBackups {
            return UIL10n.string("Every service's data AND all backups are deleted permanently, on every machine. There is no way back from this.")
        }
        if purgeData {
            return UIL10n.string("Every service's data is deleted permanently. Backups are kept. This cannot be undone.")
        }
        return UIL10n.string("All backups on this server are deleted permanently. Live data is kept. This cannot be undone.")
    }
}
