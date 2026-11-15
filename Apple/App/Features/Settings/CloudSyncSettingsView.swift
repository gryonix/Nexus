import ServerControl
import SwiftUI

/// Settings → iCloud sync
struct CloudSyncSettingsView: View {
    @ObservedObject private var sync = CloudSync.shared
    @State private var confirmingErase = false

    var body: some View {
        Form {
            CloudSyncModeSection(sync: sync)
            if sync.mode.usesPassword || sync.status == .needsPassword {
                CloudSyncPasswordSection(sync: sync)
            }
            if sync.mode.syncs {
                CloudSyncStatusSection(sync: sync)
            }
            Section {
                Button("Delete the copy in iCloud", role: .destructive) { confirmingErase = true }
                    .dangerTint()
            } footer: {
                Text("Sync uses iCloud Keychain. It has to be on: Settings → your name → iCloud → Passwords and Keychain.")
            }
        }
        .screenTitle("iCloud sync")
        .alert("Delete the copy in iCloud?", isPresented: $confirmingErase) {
            Button("Delete", role: .destructive) { sync.eraseICloudCopy() }
                .dangerTint()
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Servers stay on this device. Other devices keep what they already have.")
        }
    }
}

/// What the app keeps in iCloud, one choice
private struct CloudSyncModeSection: View {
    @ObservedObject var sync: CloudSync

    var body: some View {
        Section {
            Picker("Sync with iCloud", selection: Binding(get: { sync.mode }, set: { sync.choose($0) })) {
                ForEach(CloudSyncMode.allCases, id: \.self) { mode in
                    Text(Self.title(mode)).tag(mode)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } footer: {
            Text(Self.summary(sync.mode))
        }
    }

    static func title(_ mode: CloudSyncMode) -> LocalizedStringKey {
        switch mode {
        case .off: return "Off"
        case .apple: return "Encrypted by Apple"
        case .applePassword: return "Encrypted by Apple and a password"
        case .withoutKeys: return "Servers only, without keys"
        }
    }

    static func summary(_ mode: CloudSyncMode) -> LocalizedStringKey {
        switch mode {
        case .off:
            return "Servers and keys stay on this device."
        case .apple:
            return "Servers, SSH and VPN keys and imported VPN configurations reach your other devices. iCloud Keychain encrypts them end to end; Apple cannot read them."
        case .applePassword:
            return "As with Apple's encryption, and everything is also sealed with your own password. Even someone inside your Apple Account cannot read it without the password."
        case .withoutKeys:
            return "Only the server list and its settings are synced. Keys and passwords stay on each device; give a new device access from one that has it."
        }
    }
}
