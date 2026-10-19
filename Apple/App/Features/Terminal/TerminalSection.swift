import ServerControl
import SwiftUI

/// The fleet-wide terminal section: pick a machine, then an account
@available(macOS 15.0, *)
struct TerminalFleetView: View {
    @StateObject private var servers = ServerListViewModel()
    @StateObject private var direct = TerminalDirectHostsModel()
    @ObservedObject private var sessions = TerminalSessions.shared

    @State private var path: [Deployment] = []
    @State private var directPath: TerminalDirectHost?
    @State private var addingDirect = false
    @ObservedObject private var navigator = AppNavigator.shared
    @State private var pendingDirectID: UUID?
    @State private var editingDirect: TerminalDirectHost?
    @State private var duplicates: [(host: TerminalDirectHost, deployment: Deployment)] = []
    @AppStorage("terminal.keptSeparateHosts") private var keptSeparateRaw = ""
    #if DEBUG
    @State private var debugScreen: TerminalProfile?
    #endif

    /// Opens one directly-added machine
    private func open(_ deploymentID: UUID) {
        navigator.clearSectionServer(for: .terminal)
        if servers.deployments.isEmpty { servers.load() }
        guard let deployment = servers.deployments.first(where: { $0.id == deploymentID }) else { return }
        path = [deployment]
    }

    private func openDirect(_ id: UUID) {
        navigator.terminalDirectHostID = nil
        if let host = direct.hosts.first(where: { $0.id == id }) {
            directPath = host
            return
        }
        pendingDirectID = id
        direct.load()
    }

    var body: some View {
        fleet
    }

    @ViewBuilder
    private var fleet: some View {
        NavigationStack(path: $path) {
            fleetList
                .navigationDestination(for: Deployment.self) { deployment in
                    TerminalServerView(deployment: deployment)
                }
                .navigationDestination(item: $directPath) { host in
                    TerminalDirectHostView(host: host)
                }
                .sheet(isPresented: $addingDirect) {
                    TerminalDirectHostSheet { host, login in
                        direct.add(host, login: login)
                    }
                }
                .sheet(item: $editingDirect) { host in
                    TerminalDirectHostSheet(editing: host) { updated, _ in
                        direct.update(updated)
                    }
                }
                #if DEBUG
                .navigationDestination(item: $debugScreen) { profile in
                    if let first = servers.deployments.first {
                        TerminalScreen(deployment: first, profile: profile)
                    }
                }
                #endif
                .bottomBarClearance()
                .navigationTitle("Terminal")
                .sectionToolbar(.terminal)
                .onReceive(navigator.$terminalDirectHostID.compactMap { $0 }) { openDirect($0) }
                .onReceive(navigator.$sectionServer.compactMap {
                    $0?.tab == .terminal ? $0?.deploymentID : nil
                }) { open($0) }
                .task { if let id = navigator.sectionServer(for: .terminal) { open(id) } }
                .onChange(of: direct.hosts) { _, hosts in
                    guard let id = pendingDirectID, let host = hosts.first(where: { $0.id == id }) else { return }
                    pendingDirectID = nil
                    directPath = host
                }
                .task { if let id = navigator.terminalDirectHostID { openDirect(id) } }
                .alert("This machine is already a server",
                       isPresented: Binding(get: { !duplicates.isEmpty },
                                            set: { if !$0 { duplicates = [] } })) {
                    Button("Merge") { mergeDuplicates() }
                    Button("Keep separate", role: .cancel) { keepDuplicatesSeparate() }
                } message: {
                    Text(duplicateMessage)
                }
                .onChange(of: direct.hosts) { _, _ in recomputeDuplicates() }
                .onChange(of: servers.deployments) { _, _ in recomputeDuplicates() }
                .task {
                    servers.load()
                    direct.load()
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_OPEN_TERMINAL"] == "server",
                       let first = servers.deployments.first {
                        path = [first]
                    }
                    if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_TERMINAL"] != nil {
                        debugScreen = TerminalProfile(username: "root", secret: .appKey)
                    }
                    #endif
                }
        }
        .popToRootOnReselect(.terminal) {
            path = []
            directPath = nil
        }
    }

    @ViewBuilder
    private var fleetList: some View {
        List {
            if servers.deployments.isEmpty && direct.hosts.isEmpty {
                Section {
                    Text("Nothing to connect to yet. Add a connection to reach any machine over SSH.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(servers.deployments) { deployment in
                Section {
                    NavigationLink(value: deployment) {
                        LabeledContent {
                            if openCount(deployment) > 0 {
                                Text("\(openCount(deployment)) open")
                                    .foregroundStyle(.green)
                            } else {
                                Text(verbatim: deployment.entry.host)
                                    .foregroundStyle(.secondary)
                            }
                        } label: {
                            Text(verbatim: deployment.name)
                        }
                    }
                }
            }
            directSection
        }
    }

    /// The connections that dial a machine the fleet already manages
    private func recomputeDuplicates() {
        let kept = Set(keptSeparateRaw.split(separator: ",").map(String.init))
        var found: [(host: TerminalDirectHost, deployment: Deployment)] = []
        for host in direct.hosts where !kept.contains(host.id.uuidString) {
            let address = host.host.trimmingCharacters(in: .whitespaces).lowercased()
            guard !address.isEmpty else { continue }
            if let match = servers.deployments.first(where: { deployment in
                deployment.nodes.contains { $0.endpoint.host.lowercased() == address && $0.endpoint.port == host.port }
            }), !TerminalProfileStore(deploymentID: host.id).load().contains(where: { $0.secret == .appKey }) {
                found.append((host, match))
            }
        }
        duplicates = found
    }

    private var duplicateMessage: String {
        guard let first = duplicates.first else { return "" }
        if duplicates.count == 1 {
            return UIL10n.string(
                "“%@” connects to %@, which the server “%@” already manages. Merging keeps its saved logins and removes the duplicate row.",
                first.host.title, first.host.host, first.deployment.name)
        }
        return UIL10n.string(
            "%lld connections point at machines your servers already manage. Merging keeps their saved logins and removes the duplicate rows.",
            duplicates.count)
    }

    private func mergeDuplicates() {
        for pair in duplicates {
            direct.merge(pair.host, into: pair.deployment.id)
        }
        duplicates = []
    }

    private func keepDuplicatesSeparate() {
        var kept = Set(keptSeparateRaw.split(separator: ",").map(String.init))
        for pair in duplicates { kept.insert(pair.host.id.uuidString) }
        keptSeparateRaw = kept.sorted().joined(separator: ",")
        duplicates = []
    }

    @ViewBuilder
    private var directSection: some View {
        Section {
            ForEach(direct.hosts) { host in
                directRow(host)
            }
            .onDelete { offsets in direct.remove(atOffsets: offsets) }

            Button { addingDirect = true } label: {
                Label("Add a connection", systemImage: "plus")
            }
        } header: {
            InfoSectionHeader("Other connections", note: "Any machine you can reach over SSH — nothing has to be installed on it.")
        }
    }

    /// A tap opens the machine; the rest lives behind the "…"
    private func directRow(_ host: TerminalDirectHost) -> some View {
        Button {
            directPath = host
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: host.title)
                    Text(verbatim: address(of: host))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if openCount(host.id) > 0 {
                    Text("\(openCount(host.id)) open")
                        .foregroundStyle(.green)
                }
                Menu {
                    Button("Edit") { editingDirect = host }
                    Button("Delete", role: .destructive) { direct.remove(host) }
                        .dangerTint()
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func address(of host: TerminalDirectHost) -> String {
        let base = "\(host.username)@\(host.host)"
        return host.port == 22 ? base : "\(base):\(host.port)"
    }

    private func openCount(_ deployment: Deployment) -> Int {
        openCount(deployment.id)
    }

    private func openCount(_ id: UUID) -> Int {
        sessions.live.values.filter {
            $0.deployment.id == id && $0.state == .live
        }.count
    }
}

@available(macOS 15.0, *)
struct ServerTerminalSection: View {
    let deployment: Deployment

    @StateObject private var model: TerminalProfilesModel

    init(deployment: Deployment) {
        self.deployment = deployment
        _model = StateObject(wrappedValue: TerminalProfilesModel(deploymentID: deployment.id))
    }

    var body: some View {
        TerminalLoginsContent(deployment: deployment, model: model)
    }
}

struct TerminalSection: View {
    var body: some View {
        if #available(macOS 15.0, *) {
            TerminalFleetView()
        } else {
            ContentUnavailableView(
                "The terminal needs a newer macOS",
                systemImage: "apple.terminal",
                description: Text("An interactive shell needs macOS 15 or later."))
        }
    }
}
