import ServerControl
import SwiftUI

/// One SSH key: public data, sharing, export, install
struct SSHKeyDetailView: View {
    let keyID: UUID
    @ObservedObject private var store = UserSSHKeyStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var installing = false
    @State private var confirmingDelete = false
    @State private var sharing = false
    @State private var shareItems: [Any] = []
    @StateObject private var edits = PendingRowEdits()

    private var key: UserSSHKey? { store.keys.first { $0.id == keyID } }

    var body: some View {
        CardList {
            if let key {
                nameSection(key)
                publicSection(key)
                artSection(key)
                actionsSection(key)
            }
        }
        .screenTitle(key?.name ?? "SSH key")
        .sheet(isPresented: $installing) {
            if let key { SSHKeyInstallSheet(key: key) }
        }
        .shareSheet(isPresented: $sharing, items: shareItems)
        .pendingRowEdits(edits)
        .alert("Delete this key?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                if let key { store.delete(key) }
                dismiss()
            }
            .dangerTint()
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The private key is removed from this device. Servers that already trust it keep it.")
        }
    }

    private func nameSection(_ key: UserSSHKey) -> some View {
        Section {
            PendingTextRow(id: "ssh-key-name", title: "Name", prompt: key.name, saved: key.name, edits: edits) { name in
                store.rename(key, to: name.trimmingCharacters(in: .whitespaces))
                return true
            }
        }
    }

    private func publicSection(_ key: UserSSHKey) -> some View {
        Section("Public key") {
            Text(key.publicKey).font(.caption.monospaced()).textSelection(.enabled)
            Text(key.fingerprint).font(.caption.monospaced()).textSelection(.enabled)
            Button("Copy public key") { copyPlain(key.publicKey) }
            Button("Share public key") { share([key.publicKey]) }
        }
    }

    private func artSection(_ key: UserSSHKey) -> some View {
        Section("Randomart") {
            Text(key.randomArt)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func actionsSection(_ key: UserSSHKey) -> some View {
        Section {
            Button("Install on servers…") { installing = true }
            Button("Export private key") { Task { await exportPrivate(key) } }
            Button("Delete", role: .destructive) { confirmingDelete = true }
            .dangerTint()
        }
    }

    private func copyPlain(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func share(_ items: [Any]) {
        shareItems = items
        sharing = true
    }

    private func exportPrivate(_ key: UserSSHKey) async {
        let granted = await BiometricGate.authenticate(
            reason: UIL10n.string("Unlock to export the private key"))
        guard granted else { return }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("id_\(key.kind.rawValue)")
        do {
            try key.privateKeyPEM.write(to: file, atomically: true, encoding: .utf8)
            share([file])
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}
