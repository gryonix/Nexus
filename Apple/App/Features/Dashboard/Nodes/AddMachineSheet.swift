import ServerControl
import ServerControlSSH
import SwiftUI

/// Adds a machine to an existing deployment
struct AddMachineSheet: View {
    let deployment: Deployment
    let onAdd: (Deployment) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var port = "22"
    @State private var user = ""
    @State private var name = ""
    /// nil — dialled directly; otherwise the machine it is reached through
    @State private var parent: UUID?
    @State private var checking = false
    @State private var checked = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Address", text: $address)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    TextField("SSH port", text: $port)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    TextField("SSH user", text: $user)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                } header: {
                    InfoSectionHeader("Connection", note: "The same key this deployment already uses signs in. Add it to the machine's authorized_keys first.")
                }

                Section {
                    WrappingPicker("Reached through", selection: $parent) {
                        Text("Its own address").tag(UUID?.none)
                        ForEach(deployment.nodes) { node in
                            Text(label(for: node)).tag(UUID?.some(node.id))
                        }
                    }
                } header: {
                    InfoSectionHeader("Reached through", note: "Pick the entry server when this machine sits behind it — inside the tunnel, or on a network the app cannot reach directly.")
                }

                Section {
                    TextField("Name", text: $name)
                } header: {
                    InfoSectionHeader("Name", note: "Optional. Shown instead of the address in lists and logs.")
                }

                Section {
                    Button {
                        Task { await check() }
                    } label: {
                        HStack {
                            Label("Check the connection", systemImage: "bolt.horizontal")
                            if checking { Spacer(); ProgressView() }
                        }
                    }
                    .rowActionButtonStyle()
                    .disabled(checking || address.trimmed.isEmpty || user.trimmed.isEmpty)
                    if checked {
                        Label("The server answered.", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                    if let failure {
                        Text(failure).foregroundStyle(.red)
                    }
                } header: {
                    InfoSectionHeader("Check", note: "A server is added only after it answers, so the deployment never holds a machine the app cannot reach.")
                }
            }
            .navigationTitle(Text("Add a server"))
            .raisedNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }.disabled(!checked)
                }
            }
        }
    }

    private func label(for node: DeploymentNode) -> String {
        node.name.isEmpty ? node.endpoint.host : node.name
    }

    private var candidate: DeploymentNode {
        DeploymentNode(
            id: UUID(),
            name: name.trimmed,
            endpoint: HostEndpoint(host: address.trimmed, port: Int(port) ?? 22, user: user.trimmed),
            capabilities: [.worker],
            routedThrough: parent)
    }

    private func check() async {
        checking = true
        failure = nil
        checked = false
        defer { checking = false }

        var trial = deployment
        let node = candidate
        do {
            try trial.addNode(node)
        } catch {
            failure = DeploymentNodesView.message(for: error)
            return
        }
        do {
            let runner = try await DashboardSessionFactory.makeRunnerDetached(deployment: trial,
                                                                              shared: false)
            let result = try await runner.run("echo GRYONIXNEXUS_NODE_OK", on: node.sshHost,
                                              timeout: .seconds(25))
            await runner.disconnect()
            guard result.stdout.contains("GRYONIXNEXUS_NODE_OK") else {
                failure = UIL10n.string("The server connected but did not answer as expected.")
                return
            }
            pending = node
            checked = true
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// The node the check actually proved
    @State private var pending: DeploymentNode?

    private func add() {
        guard let node = pending else { return }
        var updated = deployment
        do {
            try updated.addNode(node)
            onAdd(updated)
            dismiss()
        } catch {
            failure = DeploymentNodesView.message(for: error)
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
