import SwiftUI

/// Entering or choosing the sync password
struct CloudSyncPasswordSection: View {
    @ObservedObject var sync: CloudSync
    @State private var password = ""
    @State private var repeated = ""
    @State private var changing = false
    @State private var working = false
    @State private var problem: String?

    private var choosingNew: Bool { changing || !sync.passwordExists }

    var body: some View {
        Section {
            SecureField(choosingNew ? "New sync password" : "Sync password", text: $password)
            if choosingNew {
                SecureField("Repeat the password", text: $repeated)
            }
            Button(choosingNew ? "Set password" : "Unlock", action: submit)
                .disabled(password.isEmpty || working || (choosingNew && password != repeated))
            if !choosingNew, sync.status != .needsPassword {
                Button("Change password") { changing = true }
            }
            if let problem {
                Text(problem).foregroundStyle(.red)
            }
        } header: {
            Text("Password")
        } footer: {
            Text("The password never leaves your devices. If it is lost, what is in iCloud cannot be read; every device asks for it once.")
        }
    }

    private func submit() {
        working = true
        problem = nil
        let entered = password
        let replacing = changing
        Task {
            do {
                if replacing {
                    try await sync.replacePassword(with: entered)
                    sync.scheduleSync(after: 0)
                } else {
                    try await sync.enter(password: entered)
                }
                password = ""
                repeated = ""
                changing = false
            } catch {
                problem = UIL10n.string("The password does not fit.")
            }
            working = false
        }
    }
}

/// When the last sync ran, and running one now
struct CloudSyncStatusSection: View {
    @ObservedObject var sync: CloudSync

    var body: some View {
        Section {
            Text(statusText).foregroundStyle(.secondary)
            Button("Sync now") { Task { await sync.sync() } }
                .disabled(sync.status == .syncing)
        }
    }

    private var statusText: String {
        switch sync.status {
        case .idle: return UIL10n.string("Not synced yet.")
        case .syncing: return UIL10n.string("Syncing…")
        case .needsPassword: return UIL10n.string("Waiting for the sync password.")
        case .failed(let message): return UIL10n.string("Sync failed: %@", message)
        case .synced(let date):
            return UIL10n.string("Synced %@", date.formatted(date: .omitted, time: .shortened))
        }
    }
}
