import ServerControl
import SwiftUI

/// One server's logins, and the way into a shell
@available(macOS 15.0, *)
struct TerminalServerView: View {
    let deployment: Deployment

    @StateObject private var model: TerminalProfilesModel
    @ObservedObject private var sessions = TerminalSessions.shared
    @State private var editing: TerminalProfile?
    @State private var adding = false
    @State private var opening: TerminalProfile?

    init(deployment: Deployment) {
        self.deployment = deployment
        _model = StateObject(wrappedValue: TerminalProfilesModel(deploymentID: deployment.id))
    }

    var body: some View {
        List {
            TerminalLoginsContent(deployment: deployment, model: model)
        }
        .bottomBarClearance()
        .navigationTitle("Terminal")
        .raisedNavigationTitle()
    }
}

@available(macOS 15.0, *)
struct TerminalLoginsContent: View {
    let deployment: Deployment
    @ObservedObject var model: TerminalProfilesModel
    var showsAccountCreation = true

    @ObservedObject private var sessions = TerminalSessions.shared
    @State private var editing: TerminalProfile?
    @State private var adding = false
    @State private var opening: TerminalProfile?

    var body: some View {
        Section {
            if model.profiles.isEmpty {
                emptyRow
            } else {
                ForEach(model.profiles) { profile in
                    row(profile)
                }
                .onDelete { offsets in model.remove(atOffsets: offsets) }
            }
            addRow
        } header: {
            InfoSectionHeader("Logins", note: "Kept in this device's Keychain, and sent nowhere but this server.")
        }

        if showsAccountCreation {
            Section {
                NavigationLink {
                    CreateShellUserSheet(deployment: deployment)
                } label: {
                    Label("Create an account on the server", systemImage: "person.badge.plus")
                }
                .infoNote("Create an account", "Needs a login that can run useradd — root, or an account with full sudo.")
            }
        }
    }

    private var addRow: some View {
        Button { adding = true } label: {
            Label("Add a login", systemImage: "plus")
        }
        .navigationDestination(item: $opening) { profile in
            TerminalScreen(deployment: deployment, profile: profile)
        }
        .sheet(isPresented: $adding) {
            TerminalLoginSheet(deployment: deployment) { profile in
                model.add(profile)
            }
        }
        .sheet(item: $editing) { profile in
            TerminalLoginSheet(deployment: deployment, editing: profile) { updated in
                model.update(updated)
            }
        }
        .task { model.load() }
    }

    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("No logins yet")
            Text("Add the account you sign in with on this server.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func row(_ profile: TerminalProfile) -> some View {
        Button {
            opening = profile
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "apple.terminal")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 28, height: 28)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: profile.username)
                    Text(verbatim: profile.kindDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if sessions.existing(for: profile)?.state == .live {
                    Text("Open")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.green.opacity(0.14), in: Capsule())
                }
                Menu {
                    Button("Edit") { editing = profile }
                    if sessions.existing(for: profile) != nil {
                        Button("Disconnect", role: .destructive) {
                            TerminalSessions.shared.end(profile)
                        }
                        .dangerTint()
                    }
                    Button("Delete", role: .destructive) { model.remove(profile) }
                        .dangerTint()
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@available(macOS 15.0, *)
@MainActor
final class TerminalProfilesModel: ObservableObject {
    @Published private(set) var profiles: [TerminalProfile] = []

    private let store: TerminalProfileStore

    init(deploymentID: UUID) {
        store = TerminalProfileStore(deploymentID: deploymentID)
    }

    func load() {
        let store = store
        Task {
            let loaded = await Task.detached { store.load() }.value
            profiles = loaded
        }
    }

    func add(_ profile: TerminalProfile) {
        profiles.append(profile)
        persist()
    }

    func update(_ profile: TerminalProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        persist()
    }

    func remove(_ profile: TerminalProfile) {
        TerminalSessions.shared.end(profile)
        profiles.removeAll { $0.id == profile.id }
        persist()
    }

    func remove(atOffsets offsets: IndexSet) {
        for index in offsets { TerminalSessions.shared.end(profiles[index]) }
        profiles.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        let snapshot = profiles
        let store = store
        Task.detached { try? store.save(snapshot) }
    }
}
