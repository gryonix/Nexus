import SwiftUI
import VPNProfile

/// Policy groups: lowest ping, or a manual choice.
struct AdvancedGroupsView: View {
    @ObservedObject var model: AdvancedVPNModel
    @State private var name = ""
    @State private var auto = true
    @State private var members: Set<String> = []

    var body: some View {
        Form {
            Section {
                ForEach(model.profile.groups) { group in groupRow(group) }
                    .onDelete { offsets in
                        let gone = Set(offsets.map { model.profile.groups[$0].id })
                        model.update { profile in
                            profile.groups.removeAll { gone.contains($0.id) }
                            if let active = profile.activeID, gone.contains(active) { profile.activeID = nil }
                        }
                    }
            }
            newGroupSection
        }
        .formStyle(.grouped)
        .screenTitle("Groups")
    }

    private func groupRow(_ group: AdvancedGroup) -> some View {
        VStack(alignment: .leading) {
            Text(verbatim: group.name)
            Text(group.mode == .auto ? "Automatic, lowest ping" : "Manual").font(.caption).foregroundStyle(.secondary)
            if group.mode == .manual {
                Picker("Use", selection: selection(of: group)) {
                    ForEach(group.memberIDs.compactMap(model.profile.server)) { Text(verbatim: $0.name).tag($0.id) }
                }
            }
        }
    }

    private func selection(of group: AdvancedGroup) -> Binding<String> {
        Binding(get: { group.chosenID ?? "" }, set: { value in
            model.update { profile in
                if let index = profile.groups.firstIndex(where: { $0.id == group.id }) {
                    profile.groups[index].selectedID = value
                }
            }
        })
    }

    private var newGroupSection: some View {
        Section("New group") {
            TextField("Name", text: $name)
            Picker("Choice", selection: $auto) {
                Text("Automatic, lowest ping").tag(true)
                Text("Manual").tag(false)
            }
            ForEach(model.profile.servers) { server in
                Toggle(isOn: Binding(get: { members.contains(server.id) }, set: { on in
                    if on { members.insert(server.id) } else { members.remove(server.id) }
                })) { Text(verbatim: server.name) }
            }
            Button("Add group") {
                let ordered = model.profile.servers.map(\.id).filter(members.contains)
                model.update { $0.groups.append(AdvancedGroup(name: name, mode: auto ? .auto : .manual, memberIDs: ordered)) }
                name = ""
                members = []
            }
            .disabled(name.isEmpty || members.isEmpty)
        }
    }
}
