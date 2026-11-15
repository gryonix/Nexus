import ServerControl
import SwiftUI

/// Settings, Scripts: the saved snippets
struct ScriptsView: View {
    @ObservedObject private var store = SavedScriptStore.shared
    @State private var editing: SavedScript?
    @State private var running: SavedScript?

    var body: some View {
        CardList {
            Section {
                if store.scripts.isEmpty { Text("No scripts yet.").foregroundStyle(.secondary) }
                ForEach(store.scripts) { script in
                    Button { running = script } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(script.name)
                            Text(script.body.components(separatedBy: "\n").first ?? "")
                                .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete script", role: .destructive) { store.delete(script) }
                        .dangerTint()
                        Button("Edit") { editing = script }.tint(.blue)
                    }
                }
            } footer: {
                Text("Scripts stay on this device. Running one always asks you to confirm.")
            }
        }
        .screenTitle("Scripts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = SavedScript(name: "", body: "") } label: {
                    Label("Add script", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editing) { script in
            ScriptEditorView(script: script) { store.save($0) }
        }
        .sheet(item: $running) { script in
            ScriptRunView(script: script)
        }
    }
}

struct ScriptEditorView: View {
    @State var script: SavedScript
    let onSave: (SavedScript) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var servers: [Deployment] = []

    var body: some View {
        NavigationStack {
            CardList {
                Section {
                    TextField("Name", text: $script.name)
                    TextEditor(text: $script.body)
                        .font(.body.monospaced())
                        .frame(minHeight: 140)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                } header: {
                    Text("Script")
                }
                Section {
                    ForEach(servers) { server in serverRow(server) }
                } header: {
                    Text("Offered for")
                } footer: {
                    Text("Leave all unticked to offer the script for every server.")
                }
            }
            .screenTitle("Script")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(script); dismiss() }.disabled(!script.isValid)
                }
            }
        }
        .task { servers = (try? FileDeploymentStore().load()) ?? [] }
    }

    private func serverRow(_ server: Deployment) -> some View {
        let on = script.deploymentIDs.contains(server.id)
        return Button {
            if on { script.deploymentIDs.removeAll { $0 == server.id } }
            else { script.deploymentIDs.append(server.id) }
        } label: {
            HStack {
                Text(server.name)
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
            }
        }
        .buttonStyle(.plain)
    }
}
