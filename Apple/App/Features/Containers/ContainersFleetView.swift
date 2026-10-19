import AgentControl
import ServerControl
import SwiftUI

@available(macOS 15.0, *)
struct ContainersFleetView: View {
    @StateObject private var servers = ServerListViewModel()
    @ObservedObject private var model = ContainersFleetViewModel.shared
    @ObservedObject private var preferences = ContainersPreferences.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var inspecting: InspectedContainer?
    @State private var busyKey: String?
    @State private var path = NavigationPath()
    @ObservedObject private var navigator = AppNavigator.shared

    private func open(_ deploymentID: UUID) {
        navigator.clearSectionServer(for: .containers)
        if servers.deployments.isEmpty { servers.load() }
        guard let deployment = servers.deployments.first(where: { $0.id == deploymentID }) else { return }
        path.append(deployment)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if servers.deployments.isEmpty {
                    Section {
                        Text("No servers yet.").foregroundStyle(.secondary)
                    }
                }
                ForEach(servers.deployments) { deployment in
                    switch preferences.layout {
                    case .list: serverSection(deployment)
                    case .byServer: serverLink(deployment)
                    }
                }
            }
            .navigationDestination(for: Deployment.self) { deployment in
                ContainersServerView(deployment: deployment, model: model,
                                     preferences: preferences)
            }
            .navigationTitle("Containers")
            .sectionToolbar(.containers) {
                Toggle("Show services this app installed",
                       isOn: $preferences.showsCatalogServices)
                WrappingPicker("Layout", selection: $preferences.layout) {
                    ForEach(ContainersLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
            }
            .onReceive(navigator.$sectionServer.compactMap {
                $0?.tab == .containers ? $0?.deploymentID : nil
            }) { open($0) }
            .task { if let id = navigator.sectionServer(for: .containers) { open(id) } }
            .refreshableWithShortcut { await model.load(servers.deployments) }
            .task {
                servers.load()
                await model.load(servers.deployments)
            }
            .onChange(of: servers.deployments) { _, deployments in
                Task { await model.load(deployments) }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await model.load(servers.deployments) }
            }
            .sheet(item: $inspecting) { inspected in
                ContainerDetailSheet(container: inspected.container) { name in
                    try await model.detail(for: name, on: inspected.deployment)
                }
            }
        }
        .popToRootOnReselect(.containers) { path = NavigationPath() }
    }

    @ViewBuilder
    private func serverSection(_ deployment: Deployment) -> some View {
        Section {
            ServerContainersDisclosure(deployment: deployment,
                                       summary: model.summary(for: deployment.id)) {
                ContainerGroupRows(deployment: deployment, model: model,
                                   preferences: preferences,
                                   inspecting: $inspecting, busyKey: $busyKey)
            }
        }
    }

    @ViewBuilder
    private func serverLink(_ deployment: Deployment) -> some View {
        Section {
            NavigationLink(value: deployment) {
                LabeledContent {
                    Text(verbatim: model.summary(for: deployment.id))
                        .foregroundStyle(.secondary)
                } label: {
                    Text(verbatim: deployment.name)
                }
            }
        }
    }
}

/// One server's fold on the fleet screen
@available(macOS 15.0, *)
private struct ServerContainersDisclosure<Content: View>: View {
    let deployment: Deployment
    let summary: String
    @ViewBuilder var content: Content

    @AppStorage private var expanded: Bool

    init(deployment: Deployment, summary: String, @ViewBuilder content: () -> Content) {
        self.deployment = deployment
        self.summary = summary
        self.content = content()
        _expanded = AppStorage(wrappedValue: true, "containers.serverExpanded.\(deployment.id)")
    }

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expanded },
            set: { newValue in withAnimation(.smooth) { expanded = newValue } }
        )) {
            content
        } label: {
            LabeledContent {
                Text(verbatim: summary).foregroundStyle(.secondary)
            } label: {
                Text(verbatim: deployment.name)
            }
        }
    }
}

@available(macOS 15.0, *)
private struct ContainersServerView: View {
    let deployment: Deployment
    @ObservedObject var model: ContainersFleetViewModel
    @ObservedObject var preferences: ContainersPreferences

    @State private var inspecting: InspectedContainer?
    @State private var busyKey: String?

    var body: some View {
        List {
            Section {
                ContainerGroupRows(deployment: deployment, model: model,
                                   preferences: preferences,
                                   inspecting: $inspecting, busyKey: $busyKey)
            }
        }
        .navigationTitle(Text(verbatim: deployment.name))
        .raisedNavigationTitle()
        .refreshableWithShortcut { await model.load([deployment]) }
        .sheet(item: $inspecting) { inspected in
            ContainerDetailSheet(container: inspected.container) { name in
                try await model.detail(for: name, on: inspected.deployment)
            }
        }
    }
}

/// Which long operation is open, and on what
@available(macOS 15.0, *)
struct ContainerOperationTarget: Identifiable, Hashable {
    let group: ContainerGroup
    let kind: ContainerOperationSheet.Kind
    var id: String { "\(group.key)/\(kind)" }
}

/// A container together with the server it runs on
struct InspectedContainer: Identifiable {
    let container: ContainerSummary
    let deployment: Deployment
    var id: String { "\(deployment.id)/\(container.name)" }
}

@available(macOS 15.0, *)
struct ContainerGroupRows: View {
    let deployment: Deployment
    @ObservedObject var model: ContainersFleetViewModel
    @ObservedObject var preferences: ContainersPreferences
    @Binding var inspecting: InspectedContainer?
    @Binding var busyKey: String?

    @State private var renaming: ContainerGroup?
    @State private var renameText = ""
    /// Which groups are open
    @State private var expandedKeys: Set<String> = []
    @State private var showingLogs: ContainerGroup?
    @State private var showingBackup: ContainerGroup?
    @State private var removing: ContainerGroup?
    @State private var operating: ContainerOperationTarget?

    var body: some View {
        content
            .sheet(item: $showingLogs) { group in
                ContainerGroupLogSheet(deployment: deployment, group: group, model: model)
            }
            .sheet(item: $showingBackup) { group in
                ContainerBackupPlanSheet(deployment: deployment, group: group, model: model)
            }
            .sheet(item: $removing) { group in
                ContainerRemovalSheet(deployment: deployment, group: group, model: model)
            }
            .sheet(item: $operating) { target in
                ContainerOperationSheet(deployment: deployment, group: target.group,
                                        kind: target.kind, model: model)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.states[deployment.id] {
        case .none, .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading what runs on this server…").foregroundStyle(.secondary)
            }
        case .needsAgent:
            Label("This server needs the management agent.", systemImage: "bolt.horizontal.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(verbatim: message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        case .loaded(let inventory):
            if let reason = inventory.unavailableReason {
                // A broken engine and an empty machine are different sentences.
                VStack(alignment: .leading, spacing: 4) {
                    Text("No container engine answered on this server")
                    Text(verbatim: reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } else if inventory.groups.isEmpty {
                Text("Nothing is running on this server.").foregroundStyle(.secondary)
            } else {
                let installed = inventory.groups.filter { $0.serviceID != nil }
                let found = inventory.groups.filter { $0.serviceID == nil }
                if preferences.showsCatalogServices && !installed.isEmpty {
                    blockHeader("Installed by this app", count: installed.count)
                    ForEach(installed) { group in
                        groupRow(group)
                    }
                }
                if !found.isEmpty {
                    blockHeader("Found on the server", count: found.count)
                    ForEach(found) { group in
                        groupRow(group)
                    }
                } else if !preferences.showsCatalogServices {
                    Text("Everything running here was installed by this app.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func blockHeader(_ title: LocalizedStringKey, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(verbatim: count.formatted())
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func groupRow(_ group: ContainerGroup) -> some View {
        let isExpanded = expandedKeys.contains(group.key)
        HStack(spacing: 10) {
            Button {
                withAnimation(.smooth) {
                    if isExpanded { expandedKeys.remove(group.key) }
                    else { expandedKeys.insert(group.key) }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 24, alignment: .leading)
                    StatusDot(status: group.status)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: group.displayName)
                            .foregroundStyle(.primary)
                        Text(subtitle(for: group))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: group.displayName))
            .accessibilityHint(isExpanded ? Text("Collapse") : Text("Expand"))
            if busyKey == group.key {
                ProgressView().controlSize(.small)
            } else {
                actions(for: group)
            }
        }
        .alert("Rename", isPresented: Binding(
            get: { renaming?.key == group.key },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Save") {
                Task { await model.rename(group.key, to: renameText, on: deployment) }
                renaming = nil
            }
            if group.isRenamed {
                Button("Use the detected name") {
                    Task { await model.rename(group.key, to: "", on: deployment) }
                    renaming = nil
                }
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: {
            Text("Detected as “\(group.derivedName)”. The name is stored on the server, so your other devices see it too.")
        }
        if isExpanded {
            ForEach(group.containers) { container in
                Button {
                    inspecting = InspectedContainer(container: container, deployment: deployment)
                } label: {
                    containerRow(container)
                }
                .buttonStyle(.plain)
                .padding(.leading, 34)
            }
            if !group.configFiles.isEmpty {
                Text(verbatim: group.configFiles.joined(separator: "\n"))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 34)
            }
        }
    }

    private func subtitle(for group: ContainerGroup) -> LocalizedStringKey {
        group.isComposeProject ? "Compose project" : "Standalone container"
    }

    private func actions(for group: ContainerGroup) -> some View {
        Menu {
            Button {
                renameText = group.displayName
                renaming = group
            } label: {
                Label("Rename…", systemImage: "pencil")
            }
            Button { showingLogs = group } label: { Label("Logs", systemImage: "doc.text") }
            Divider()
            Button { act(group, .start) } label: { Label("Start", systemImage: "play") }
            Button { act(group, .restart) } label: { Label("Restart", systemImage: "arrow.clockwise") }
            Button(role: .destructive) { act(group, .stop) } label: {
                Label("Stop", systemImage: "stop")
            }
            .dangerTint()
            Divider()
            Button { showingBackup = group } label: { Label("Backup…", systemImage: "externaldrive") }
            Button { operating = ContainerOperationTarget(group: group, kind: .backup) } label: {
                Label("Back up now", systemImage: "arrow.down.doc")
            }
            Button { operating = ContainerOperationTarget(group: group, kind: .update) } label: {
                Label("Update", systemImage: "arrow.up.circle")
            }
            Divider()
            Button(role: .destructive) { removing = group } label: {
                Label("Remove…", systemImage: "trash")
            }
            .dangerTint()
        } label: {
            Label("Actions", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
        }
    }

    private func containerRow(_ container: ContainerSummary) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: container.name).font(.callout)
                Text(verbatim: container.image)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !container.ports.isEmpty {
                    Text(verbatim: container.ports)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(verbatim: container.state).font(.caption).foregroundStyle(.secondary)
                if !container.health.isEmpty {
                    Text(verbatim: container.health)
                        .font(.caption2)
                        .foregroundStyle(container.health == "healthy" ? .green : .orange)
                }
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func act(_ group: ContainerGroup, _ action: ContainerAction) {
        busyKey = group.key
        Task {
            await model.control(group.key, action: action, on: deployment)
            busyKey = nil
        }
    }
}

/// The status of a whole group, as a dot
@available(macOS 15.0, *)
private struct StatusDot: View {
    let status: ContainerGroupStatus

    var body: some View {
        Circle().fill(colour).frame(width: 9, height: 9)
    }

    private var colour: Color {
        switch status {
        case .running: return .green
        case .partial: return .orange
        case .error: return .red
        case .stopped, .unknown: return .secondary
        }
    }
}

enum ContainersLayout: String, CaseIterable, Identifiable {
    /// Every server on one screen, each one foldable
    case list
    case byServer

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .list: return "All servers at once"
        case .byServer: return "One server at a time"
        }
    }
}

@MainActor
final class ContainersPreferences: ObservableObject {
    static let shared = ContainersPreferences()

    private enum Keys {
        static let showsCatalogServices = "containers.showsCatalogServices"
        static let layout = "containers.layout"
    }

    /// Everything at once, or one server at a time
    @Published var layout: ContainersLayout {
        didSet { defaults.set(layout.rawValue, forKey: Keys.layout) }
    }

    @Published var showsCatalogServices: Bool {
        didSet { defaults.set(showsCatalogServices, forKey: Keys.showsCatalogServices) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsCatalogServices = defaults.object(forKey: Keys.showsCatalogServices) as? Bool ?? true
        layout = ContainersLayout(rawValue: defaults.string(forKey: Keys.layout) ?? "") ?? .list
    }
}

/// The section as both shells mount it
struct ContainersSection: View {
    var body: some View {
        if #available(macOS 15.0, *) {
            ContainersFleetView()
        } else {
            ContentUnavailableView(
                "Containers need a newer macOS",
                systemImage: "shippingbox",
                description: Text("This section talks to the servers' management agent, which needs macOS 15 or later."))
        }
    }
}
