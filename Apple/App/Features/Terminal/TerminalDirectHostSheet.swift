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
    @State private var via: TerminalVia?

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

                TerminalViaSection(via: $via)

                if editing == nil {
                    SSHSecretSection(draft: $draft, appKeyIsInstalled: false)
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .screenTitle(editing == nil ? "New connection" : "Edit connection")
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
        via = editing.via
    }

    private func save() {
        guard let parsedPort else { return }
        let account = username.trimmingCharacters(in: .whitespaces)
        let saved = TerminalDirectHost(id: editing?.id ?? UUID(),
                                       name: name.trimmingCharacters(in: .whitespaces),
                                       host: host.trimmingCharacters(in: .whitespaces),
                                       port: parsedPort,
                                       username: account,
                                       via: via)
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

/// Picks the managed machine a connection goes through
@available(macOS 15.0, *)
struct TerminalViaSection: View {
    @Binding var via: TerminalVia?
    @State private var choices: [Choice] = []

    struct Choice: Hashable {
        let via: TerminalVia
        let title: String
    }

    var body: some View {
        Section {
            Picker("Through a server", selection: $via) {
                Text("Directly").tag(TerminalVia?.none)
                ForEach(choices, id: \.self) { choice in
                    Text(choice.title).tag(TerminalVia?.some(choice.via))
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("For a machine in a home network: the app signs in to the chosen machine first and connects from there.")
                if via != nil {
                    Text("Address: the one the chosen machine reaches it by, for example 192.168.1.20 at home. The chosen machine's own name or address opens that machine.")
                }
            }
        }
        .task { choices = Self.choices() }
    }

    /// Managed machines with an address, as choices
    static func choices(in fleet: [Deployment] = (try? FileDeploymentStore().load()) ?? []) -> [Choice] {
        fleet.filter { !DemoServer.isDemo($0) }.flatMap { server in
            server.nodes.enumerated().compactMap { index, node -> Choice? in
                guard !node.endpoint.host.isEmpty else { return nil }
                let via = TerminalVia(server: server.id, node: index == 0 ? nil : node.id)
                let machine = node.name.isEmpty ? node.endpoint.host : node.name
                let title = index == 0 ? server.name : UIL10n.string("%@ → %@", server.name, machine)
                return Choice(via: via, title: title)
            }
        }
    }
}
