import SwiftUI

struct SecuritySettingsView: View {
    @AppStorage(SecuritySettings.gateAccessScreenKey)
    private var gateAccessScreen = true
    @AppStorage(SecuritySettings.gateRevealKey)
    private var gateReveal = true
    @AppStorage(SecuritySettings.gateExportKey)
    private var gateExport = true

    @State private var unlocked = false
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CardList {
            if unlocked {
                Section {
                    Toggle("Login & Passwords screen", isOn: $gateAccessScreen)
                    Toggle("Revealing a saved password", isOn: $gateReveal)
                    Toggle("Exporting or sharing setup files", isOn: $gateExport)
                } header: {
                    InfoSectionHeader("Require unlock", note: "Face ID, Touch ID or your device passcode guards these actions.")
                }
            } else {
                Section {
                    Label(failed ? "Not unlocked." : "Unlocking…",
                          systemImage: failed ? "lock.trianglebadge.exclamationmark" : "lock")
                        .foregroundStyle(.secondary)
                    if failed {
                        Button("Try again") { Task { await unlock() } }
                    }
                }
            }
        }
        .navigationTitle("Security")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            guard !unlocked else { return }
            await unlock()
        }
    }

    private func unlock() async {
        failed = false
        let granted = await BiometricGate.authenticate(
            reason: UIL10n.string("Unlock to change the security settings"))
        if granted {
            unlocked = true
        } else {
            failed = true
        }
    }
}

#Preview {
    NavigationStack { SecuritySettingsView() }
}
