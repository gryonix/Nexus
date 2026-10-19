import Foundation
import ServerControl
import SwiftUI

/// Add or edit a machine the app never installed
@available(macOS 15.0, *)
struct TerminalDirectHostSheet: View {
    var editing: TerminalDirectHost?
    let onSave: (TerminalDirectHost, TerminalProfile?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var draft = SSHSecretDraft(kind: .password)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Address", text: $host)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled()
                    TextField("Port", text: $port)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    TextField("Name (optional)", text: $name)
                } header: {
                    InfoSectionHeader("Address", note: "A host name or IP address. Without a name, the list shows the address.")
                }

                Section {
                    TextField("User name", text: $username)
                        .textContentType(.username)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                } header: {
                    InfoSectionHeader("User name", note: "The account to sign in as.")
                }

                if editing == nil {
                    SSHSecretSection(draft: $draft, appKeyIsInstalled: false)
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle(editing == nil ? "New connection" : "Edit connection")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .task { fill() }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 480)
        #endif
    }

    private var parsedPort: Int? {
        guard let value = Int(port.trimmingCharacters(in: .whitespaces)),
              (1...65535).contains(value) else { return nil }
        return value
    }

    private var canSave: Bool {
        guard !host.trimmingCharacters(in: .whitespaces).isEmpty,
              !username.trimmingCharacters(in: .whitespaces).isEmpty,
              parsedPort != nil else { return false }
        return editing != nil || draft.isComplete
    }

    private func fill() {
        guard let editing else { return }
        name = editing.name
        host = editing.host
        port = String(editing.port)
        username = editing.username
    }

    private func save() {
        guard let parsedPort else { return }
        let account = username.trimmingCharacters(in: .whitespaces)
        let saved = TerminalDirectHost(id: editing?.id ?? UUID(),
                                       name: name.trimmingCharacters(in: .whitespaces),
                                       host: host.trimmingCharacters(in: .whitespaces),
                                       port: parsedPort,
                                       username: account)
        guard editing == nil else {
            onSave(saved, nil)
            dismiss()
            return
        }
        guard let secret = draft.secret() else { return }
        onSave(saved, TerminalProfile(username: account, secret: secret))
        dismiss()
    }
}
