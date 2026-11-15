import CryptoKit
import ServerControl
import ServerControlSSH
import SwiftUI

/// Every machine of a server, as the chosen account
@available(macOS 15.0, *)
struct TerminalMachinesSection: View {
    let deployment: Deployment

    @ObservedObject private var sessions = TerminalSessions.shared
    @StateObject private var accounts: TerminalMachineUsers
    @State private var opening: TerminalProfile?

    init(deployment: Deployment) {
        self.deployment = deployment
        _accounts = StateObject(wrappedValue: TerminalMachineUsers(deployment: deployment))
    }

    var body: some View {
        let machines = Self.machineLogins(for: deployment, users: accounts)
        if !machines.isEmpty {
            Section {
                ForEach(machines) { profile in
                    row(profile)
                }
                .navigationDestination(item: $opening) { profile in
                    TerminalScreen(deployment: deployment, profile: profile)
                }
            } header: {
                InfoSectionHeader("Machines", note: "Signs in as the account chosen next to the machine — the app's own unless you pick another. When that account does not have the app's key yet, the app puts it there first. A machine behind the VPS is reached through it on its own.")
            } footer: {
                if let failure = accounts.failure { Text(verbatim: failure) }
            }
            .task { await accounts.load() }
        }
    }

    /// One login per machine, as its chosen account
    static func machineLogins(for deployment: Deployment, users: TerminalMachineUsers) -> [TerminalProfile] {
        guard deployment.dashboardConfig.isConnectable else { return [] }
        return deployment.nodes.filter { !$0.endpoint.host.isEmpty }.map { node in
            let user = users.user(of: node)
            let id = user == users.appUser(of: node) ? node.id : profileID(node.id, user)
            return TerminalProfile(id: id, username: user, secret: .appKey, nodeID: node.id)
        }
    }

    /// The same id for the same machine and account
    static func profileID(_ node: UUID, _ user: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data("\(node.uuidString)/\(user)".utf8)))
        return UUID(uuid: (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
                           digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]))
    }

    private func node(of profile: TerminalProfile) -> DeploymentNode? {
        deployment.nodes.first { $0.id == profile.nodeID }
    }

    private func title(of node: DeploymentNode?) -> String {
        guard let node else { return deployment.name }
        return deployment.metricsMachineLabel(for: node.sshHost) ?? deployment.name
    }

    private func detail(of profile: TerminalProfile, node: DeploymentNode?) -> String {
        let address = "\(profile.username)@\(node?.endpoint.host ?? "")"
        guard let node, node.routedThrough != nil else { return address }
        let path = TerminalEndpointBuilder.pathInUse(
            choice: HomePathChoice.load(for: deployment.id), deploymentID: deployment.id, nodeID: node.id)
        return UIL10n.string(path == .localNetwork ? "%@ · over the local network" : "%@ · through the VPS", address)
    }

    private func open(_ profile: TerminalProfile) {
        guard let node = node(of: profile) else { return }
        Task {
            if await accounts.prepare(node) { opening = profile }
        }
    }

    private func row(_ profile: TerminalProfile) -> some View {
        let node = node(of: profile)
        return HStack(spacing: 10) {
            Button { open(profile) } label: {
                HStack(spacing: 12) {
                    Image(systemName: node?.routedThrough == nil ? "server.rack" : "house")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.tint)
                        .frame(width: 28, height: 28)
                        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: title(of: node))
                        Text(verbatim: detail(of: profile, node: node))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if accounts.preparing == node?.id {
                        ProgressView().controlSize(.small)
                    } else if sessions.existing(for: profile)?.state == .live {
                        openBadge
                    }
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let node, accounts.lists(node) { accountMenu(node) }
        }
    }

    private func accountMenu(_ node: DeploymentNode) -> some View {
        Menu {
            Picker("Account", selection: Binding(
                get: { accounts.user(of: node) },
                set: { accounts.choose($0, for: node) }
            )) {
                ForEach(names(on: node), id: \.self) { name in
                    Text(verbatim: menuTitle(name, on: node)).tag(name)
                }
            }
        } label: {
            Label("Account", systemImage: "person.crop.circle")
                .labelStyle(.iconOnly)
                .foregroundStyle(.tint)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// The machine's accounts, the app's own first
    private func names(on node: DeploymentNode) -> [String] {
        let own = accounts.appUser(of: node)
        let listed = (accounts.users[node.id] ?? []).map(\.name).filter { $0 != own }
        return [own] + listed
    }

    private func menuTitle(_ name: String, on node: DeploymentNode) -> String {
        if name == accounts.appUser(of: node) { return UIL10n.string("%@ (the app's)", name) }
        let hasKey = accounts.users[node.id]?.first { $0.name == name }?.appKeyPresent == true
        return hasKey ? name : UIL10n.string("%@ · the key will be added", name)
    }

    private var openBadge: some View {
        Text("Open")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.green)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.green.opacity(0.14), in: Capsule())
    }
}
