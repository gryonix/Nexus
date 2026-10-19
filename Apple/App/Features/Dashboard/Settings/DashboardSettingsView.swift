import ServerControl
import SwiftUI

struct DeploymentKeyView: View {
    let deploymentID: UUID
    let onCredentialsChanged: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var publicKey: String = ""
    @State private var keyError: String?
    @State private var confirmingKeyRegeneration = false
    @State private var confirmingPinReset = false

    var body: some View {
        NavigationStack {
            Form {
                connectionSection

                if !publicKey.isEmpty {
                    AdvancedSection {
                        Text(publicKey)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(3)
                        Button {
                            copy(publicKey)
                        } label: {
                            Label("Copy Public Key", systemImage: "doc.on.doc")
                        }
                        .rowActionButtonStyle()
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmingPinReset = true
                    } label: {
                        Label("Reset Pinned Host Keys", systemImage: "exclamationmark.shield")
                    }
                    .rowActionButtonStyle()
                    .dangerTint()
                } footer: {
                    Text("The host key is remembered on the first connection. Reset it if the server was reinstalled — otherwise the connection will be rejected.")
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 520, minHeight: 480)
            #endif
            .navigationTitle("Access")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadKey() }
            .alert("Create a new SSH key?", isPresented: $confirmingKeyRegeneration) {
                Button("Create New", role: .destructive) { Task { await regenerateKey() } }
                .dangerTint()
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The old key will be deleted. The dashboard will not be able to connect until the new public key is in authorized_keys on the servers.")
            }
            .alert("Reset the pinned host keys?", isPresented: $confirmingPinReset) {
                Button("Reset", role: .destructive) {
                    HostKeyPinStore(deploymentID: deploymentID).resetAll()
                    onCredentialsChanged()
                }
                .dangerTint()
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The next connection will trust whatever keys the servers present again.")
            }
        }
    }

    @ViewBuilder
    private var connectionSection: some View {
        Section {
            if publicKey.isEmpty {
                Text(keyError ?? UIL10n.string("No key created yet"))
                    .font(.caption)
                    .foregroundStyle(keyError == nil ? Color.secondary : Color.red)
            }

            Button {
                copy(grantCommand)
            } label: {
                Label("Copy Command", systemImage: "terminal")
            }
            .rowActionButtonStyle()
            .disabled(publicKey.isEmpty)

            Button(role: .destructive) {
                confirmingKeyRegeneration = true
            } label: {
                Label("Create New Key", systemImage: "key.horizontal")
            }
            .rowActionButtonStyle()
            .dangerTint()
        } header: {
            InfoSectionHeader("App SSH key", note: "The private key is stored only in this device's Keychain. The public key is added to servers by the setup scripts (\"Agent access\" in the configurator) or manually to authorized_keys. The copied command authorizes the account you run it as — sudo in front is fine — and prints which account that was.")
        }
    }

    private func loadKey() async {
        let deploymentID = deploymentID
        let result = await Task.detached(priority: .userInitiated) { () -> Result<String, Error> in
            do { return .success(try KeychainSSHIdentityStore(deploymentID: deploymentID).loadOrGenerate().publicKeyOpenSSH) }
            catch { return .failure(error) }
        }.value
        switch result {
        case .success(let key): publicKey = key; keyError = nil
        case .failure(let error):
            keyError = (error as? LocalizedError)?.errorDescription ?? UIL10n.string("Could not read the key from the Keychain")
        }
    }

    private func regenerateKey() async {
        let deploymentID = deploymentID
        let result = await Task.detached(priority: .userInitiated) { () -> Result<String, Error> in
            do {
                let store = KeychainSSHIdentityStore(deploymentID: deploymentID)
                try store.delete()
                return .success(try store.loadOrGenerate().publicKeyOpenSSH)
            } catch { return .failure(error) }
        }.value
        switch result {
        case .success(let key):
            publicKey = key
            keyError = nil
            onCredentialsChanged()
        case .failure(let error):
            keyError = (error as? LocalizedError)?.errorDescription ?? UIL10n.string("Could not create the key")
        }
    }

    private var grantCommand: String {
        AccessGrantCommand.command(publicKey: publicKey)
    }

    private func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}

#Preview {
    DeploymentKeyView(deploymentID: UUID()) {}
}
