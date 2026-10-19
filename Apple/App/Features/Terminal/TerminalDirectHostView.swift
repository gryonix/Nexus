import Foundation
import ServerControl
import SwiftUI

/// One direct host's logins
@available(macOS 15.0, *)
struct TerminalDirectHostView: View {
    let host: TerminalDirectHost

    @StateObject private var model: TerminalProfilesModel
    @State private var showingKey = false

    init(host: TerminalDirectHost) {
        self.host = host
        _model = StateObject(wrappedValue: TerminalProfilesModel(deploymentID: host.id))
    }

    var body: some View {
        List {
            TerminalLoginsContent(deployment: host.deployment,
                                  model: model,
                                  showsAccountCreation: false)

            Section {
                Button { showingKey = true } label: {
                    Label("App SSH key", systemImage: "key")
                }
                .infoNote("App SSH key", "To sign in with this app's key, copy it into the account's authorized_keys on this machine first.")
            }
        }
        .sheet(isPresented: $showingKey) {
            DeploymentKeyView(deploymentID: host.id) {
                TerminalSessions.shared.endAll(for: host.id)
            }
        }
        .bottomBarClearance()
        .navigationTitle(Text(verbatim: host.title))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

@available(macOS 15.0, *)
@MainActor
final class TerminalDirectHostsModel: ObservableObject {
    @Published private(set) var hosts: [TerminalDirectHost] = []

    private let store: TerminalDirectHostStore

    init(store: TerminalDirectHostStore = TerminalDirectHostStore()) {
        self.store = store
    }

    func load() {
        let store = store
        Task {
            let loaded = await Task.detached { (try? store.load()) ?? [] }.value
            hosts = loaded
        }
    }

    func add(_ host: TerminalDirectHost, login: TerminalProfile?) {
        hosts.append(host)
        let store = store
        let snapshot = hosts
        Task.detached {
            try? store.save(snapshot)
            guard let login else { return }
            try? TerminalProfileStore(deploymentID: host.id).save([login])
        }
    }

    func update(_ host: TerminalDirectHost) {
        guard let index = hosts.firstIndex(where: { $0.id == host.id }) else { return }
        hosts[index] = host
        TerminalSessions.shared.endAll(for: host.id)
        persist()
    }

    func merge(_ host: TerminalDirectHost, into deploymentID: UUID) {
        TerminalSessions.shared.endAll(for: host.id)
        hosts.removeAll { $0.id == host.id }
        persist()
        let id = host.id
        Task.detached {
            let carried = TerminalProfileStore(deploymentID: id).load()
            if !carried.isEmpty {
                let target = TerminalProfileStore(deploymentID: deploymentID)
                var existing = target.load()
                for profile in carried where !existing.contains(where: {
                    $0.username == profile.username && $0.secret == profile.secret
                }) {
                    existing.append(TerminalProfile(username: profile.username,
                                                    secret: profile.secret))
                }
                try? target.save(existing)
            }
            TerminalProfileStore(deploymentID: id).delete()
            try? KeychainSSHIdentityStore(deploymentID: id).delete()
            HostKeyPinStore(deploymentID: id).resetAll()
        }
    }

    /// Removes the host and everything stored under its id
    func remove(_ host: TerminalDirectHost) {
        TerminalSessions.shared.endAll(for: host.id)
        hosts.removeAll { $0.id == host.id }
        persist()
        let id = host.id
        Task.detached {
            TerminalProfileStore(deploymentID: id).delete()
            try? KeychainSSHIdentityStore(deploymentID: id).delete()
            HostKeyPinStore(deploymentID: id).resetAll()
        }
    }

    func remove(atOffsets offsets: IndexSet) {
        for host in offsets.map({ hosts[$0] }) { remove(host) }
    }

    private func persist() {
        let snapshot = hosts
        let store = store
        Task.detached { try? store.save(snapshot) }
    }
}
