import Foundation
import ServerControl
import SwiftUI

/// Add or edit one login
@available(macOS 15.0, *)
struct TerminalLoginSheet: View {
    let deployment: Deployment
    var editing: TerminalProfile?
    let onSave: (TerminalProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var nodeID: UUID?
    @State private var draft = SSHSecretDraft()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("User name", text: $username)
                        .textContentType(.username)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    if deployment.nodes.count > 1 {
                        WrappingPicker("Machine", selection: $nodeID) {
                            ForEach(deployment.nodes) { node in
                                Text(verbatim: label(for: node)).tag(Optional(node.id))
                            }
                        }
                    }
                } header: {
                    InfoSectionHeader("Login", note: "The account on the server, not the one this app manages it with.")
                }

                SSHSecretSection(draft: $draft, appKeyIsInstalled: true)
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle(editing == nil ? "New login" : "Edit login")
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
        .frame(minWidth: 480, minHeight: 420)
        #endif
    }

    private var canSave: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && draft.isComplete
    }

    private func fill() {
        guard let editing else { return }
        username = editing.username
        nodeID = editing.nodeID
        draft = SSHSecretDraft(editing: editing.secret)
    }

    private func save() {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard let secret = draft.secret(keeping: editing?.secret) else { return }
        onSave(TerminalProfile(id: editing?.id ?? UUID(), username: name,
                               secret: secret, nodeID: nodeID))
        dismiss()
    }

    private func label(for node: DeploymentNode) -> String {
        if !node.name.isEmpty { return node.name }
        return node.endpoint.host
    }
}
