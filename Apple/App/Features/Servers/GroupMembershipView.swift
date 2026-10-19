import ServerControl
import SwiftUI

/// `sheet(item:)` needs something identifiable, and a group is a word
struct GroupTarget: Identifiable {
    let name: String
    var id: String { name }
}

/// Which servers a group holds
struct GroupMembershipView: View {
    let group: String
    let deployments: [Deployment]
    let onSave: (Set<UUID>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<UUID>

    init(group: String, deployments: [Deployment], onSave: @escaping (Set<UUID>) -> Void) {
        self.group = group
        self.deployments = deployments
        self.onSave = onSave
        _chosen = State(initialValue: Set(
            ServerGroups.members(of: group, in: deployments).map(\.id)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(deployments) { deployment in
                        Button {
                            if chosen.contains(deployment.id) {
                                chosen.remove(deployment.id)
                            } else {
                                chosen.insert(deployment.id)
                            }
                        } label: {
                            LabeledContent {
                                if chosen.contains(deployment.id) {
                                    Image(systemName: "checkmark")
                                }
                            } label: {
                                Text(verbatim: deployment.name)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(verbatim: group)
                        Spacer()
                        InfoNote("Group", "A group is a label on its servers. One with no servers left disappears.")
                    }
                }
            }
            .buttonStyle(.borderless)
            .navigationTitle("Servers in group")
            .raisedNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(chosen)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
