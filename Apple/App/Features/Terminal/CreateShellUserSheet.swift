import ServerControl
import SwiftUI

@available(macOS 15.0, *)
struct CreateShellUserSheet: View {
    let deployment: Deployment

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var withSudo = false
    @State private var running = false
    @State private var result: Outcome?

    private enum Outcome {
        case created(String)
        case failed(String)
    }

    var body: some View {
        Form {
            Section {
                TextField("User name", text: $name)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                Toggle("Full sudo without a password", isOn: $withSudo)
            } footer: {
                if !name.isEmpty && !ShellUserCommand.isValidName(name) {
                    Text("Lower-case letters, digits, - and _; must start with a letter. Names the system already uses are refused.")
                        .foregroundStyle(.red)
                } else {
                    Text("The account gets a home directory, a shell, and this app's public key — so you can sign in to it from the terminal straight away.")
                }
            }

            Section {
                Button {
                    Task { await run() }
                } label: {
                    if running {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Creating…")
                        }
                    } else {
                        Text("Create the account")
                    }
                }
                .rowActionButtonStyle()
                .disabled(running || !ShellUserCommand.isValidName(name))
            } header: {
                InfoSectionHeader("How it runs", note: "Runs over SSH as the account this app signs in with. It needs root, or full sudo — a management user created by an install does not have it.")
            }

            if let result {
                Section {
                    switch result {
                    case .created(let account):
                        Label("Created “\(account)”. Add it as a login above.", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    case .failed(let message):
                        Text(verbatim: message)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle("New account")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func run() async {
        running = true
        defer { running = false }
        let deployment = deployment
        let account = name
        let sudo = withSudo
        do {
            let identity = try await Task.detached {
                try KeychainSSHIdentityStore(deploymentID: deployment.id).loadOrGenerate()
            }.value
            guard let command = ShellUserCommand.command(name: account,
                                                         publicKey: identity.publicKeyOpenSSH,
                                                         sudo: sudo) else {
                result = .failed(UIL10n.string("that name cannot be used"))
                return
            }
            let runner = try await DashboardSessionFactory.makeRunnerDetached(deployment: deployment)
            let output = try await runner.run(command, on: .vps, timeout: .seconds(60))
            let text = (output.stdout + "\n" + output.stderr)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if text.contains(ShellUserCommand.marker) {
                result = .created(account)
            } else {
                result = .failed(text)
            }
        } catch {
            result = .failed(error.localizedDescription)
        }
    }
}
