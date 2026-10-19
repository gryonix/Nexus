import ServerControl
import ServiceCatalog
import SwiftUI

struct DeploymentNodesView: View {
    @State private var deployment: Deployment
    /// Persists an edited deployment
    private let onUpdate: ((Deployment) -> Void)?

    @State private var addingMachine = false
    @State private var editError: String?
    @State private var pendingMove: ServiceMoveRoute?
    @State private var moveRefusal: String?
    @State private var interruptedMove: ServiceMoveRecord?
    /// The same lever the dashboard's service list uses
    @ObservedObject private var tabs = TabBarSettings.shared

    init(deployment: Deployment, onUpdate: ((Deployment) -> Void)? = nil) {
        _deployment = State(initialValue: deployment)
        self.onUpdate = onUpdate
    }
    private var placement: ServicePlacement { deployment.placement ?? ServicePlacement() }

    @ViewBuilder private var nodeSections: some View {
        ForEach(deployment.nodes) { node in
            Section {
                LabeledContent("Address") {
                    Text(verbatim: node.endpoint.host).foregroundStyle(.secondary)
                }
                LabeledContent("Role") {
                    Text(role(of: node)).foregroundStyle(.secondary)
                }
                servicesRows(for: node)
                if node.legacySlot == nil, onUpdate != nil {
                    Button(role: .destructive) {
                        remove(node)
                    } label: {
                        Label("Remove this server", systemImage: "trash")
                    }
                    .rowActionButtonStyle()
                    .dangerTint()
                }
            } header: {
                Text(title(for: node))
            } footer: {
                Text(explanation(for: node))
            }
        }
    }

    var body: some View {
        CardList {
            nodeSections

            if onUpdate != nil {
                Section {
                    Button {
                        addingMachine = true
                    } label: {
                        Label("Add a server", systemImage: "plus.circle")
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Another machine this deployment runs services on. The connection is checked before it is added.")
                        if workers.count > 1 {
                            Text("Picking another machine moves the service there. Its data is copied over, and the old copy stays, stopped.")
                        }
                    }
                }
            }

            interruptedMoveSection

            if !deployment.placementProblems(placement).isEmpty {
                Section {
                    ForEach(unroutable, id: \.rawValue) { service in
                        Label(displayName(of: service), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Cannot be reached")
                } footer: {
                    Text("These services run on a server that does not answer on the public address itself. Install a mesh so the entry server can reach it.")
                }
            }
        }
        .navigationTitle(Text("Servers"))
        .raisedNavigationTitle()
        .sheet(isPresented: $addingMachine) {
            AddMachineSheet(deployment: deployment) { updated in
                deployment = updated
                onUpdate?(updated)
            }
        }
        .alert("Cannot change the servers", isPresented: Binding(
            get: { editError != nil }, set: { if !$0 { editError = nil } })) {
            Button("OK", role: .cancel) { editError = nil }
        } message: {
            Text(editError ?? "")
        }
        .alert("Cannot move this service", isPresented: Binding(
            get: { moveRefusal != nil }, set: { if !$0 { moveRefusal = nil } })) {
            Button("OK", role: .cancel) { moveRefusal = nil }
        } message: {
            Text(moveRefusal ?? "")
        }
        .alert(moveTitle, isPresented: Binding(
            get: { pendingMove != nil }, set: { if !$0 { pendingMove = nil } })) {
            Button("Move") { startMove() }
            Button("Cancel", role: .cancel) { pendingMove = nil }
        } message: {
            Text("The service's data is copied to the new machine. The old copy is stopped and its data kept. The entry server then sends visitors to the new machine. The service is unavailable for a few minutes while this happens, and if anything fails the old copy is started again.\n\nChanges made in the seconds between the copy and the stop are not carried over.")
        }
        .onAppear { refreshInterruptedMove() }
    }

    private func remove(_ node: DeploymentNode) {
        var updated = deployment
        do {
            try updated.removeNode(node.id)
            deployment = updated
            onUpdate?(updated)
        } catch {
            editError = Self.message(for: error)
        }
    }

    static func message(for error: Error) -> String {
        switch error as? Deployment.NodeEditError {
        case .noAddress: return UIL10n.string("Enter the address of the server.")
        case .unknownParent: return UIL10n.string("That server is reached through a machine this deployment does not have.")
        case .parentLoop: return UIL10n.string("Those servers would only be reachable through each other.")
        case .stillAParent: return UIL10n.string("Other servers are reached through this one. Remove them first.")
        case .lastWorker: return UIL10n.string("A deployment needs at least one server that runs services.")
        case nil: return error.localizedDescription
        }
    }

    // MARK: - Rows

    @ViewBuilder private func servicesRows(for node: DeploymentNode) -> some View {
        let running = services(on: node)
        if running.isEmpty {
            Text("Runs no services.").foregroundStyle(.secondary)
        } else if tabs.groupsServices(in: running) {
            let grouped = groups(of: running)
            ForEach(grouped.categories, id: \.category) { group in
                NodeServiceCategoryRow(storageKey: foldKey(node: node, category: group.category),
                                       category: group.category,
                                       count: group.services.count) {
                    ForEach(group.services, id: \.rawValue) { service in
                        serviceRow(service, on: node)
                    }
                }
            }
            ForEach(grouped.uncategorised, id: \.rawValue) { service in
                serviceRow(service, on: node)
            }
        } else {
            ForEach(running, id: \.rawValue) { service in
                serviceRow(service, on: node)
            }
        }
    }

    @ViewBuilder private func serviceRow(_ service: ServiceID, on node: DeploymentNode) -> some View {
        if onUpdate != nil, workers.count > 1 {
            Menu {
                ForEach(workers) { target in
                    // The tick belongs after the words — see `MenuChoice`.
                    VerbatimMenuChoice(machineName(target), picked: target.id == node.id) {
                        if target.id != node.id { requestMove(service, to: target) }
                    }
                }
            } label: {
                LabeledContent(displayName(of: service)) {
                    Text(delivery(of: service)).foregroundStyle(.secondary)
                }
            }
        } else {
            LabeledContent(displayName(of: service)) {
                Text(delivery(of: service)).foregroundStyle(.secondary)
            }
        }
    }

    private func foldKey(node: DeploymentNode, category: ServiceCategory) -> String {
        "nodeServiceCategoryExpanded.\(deployment.id).\(node.id).\(category.id)"
    }

    private func groups(of services: [ServiceID])
        -> (categories: [(category: ServiceCategory, services: [ServiceID])], uncategorised: [ServiceID]) {
        var order: [ServiceCategory] = []
        var buckets: [ServiceCategory: [ServiceID]] = [:]
        var uncategorised: [ServiceID] = []
        for service in services {
            guard let known = ServiceRegistry.all.first(where: { $0.id == service }) else {
                uncategorised.append(service)
                continue
            }
            let category = known.displayCategory
            if buckets[category] == nil {
                buckets[category] = []
                order.append(category)
            }
            buckets[category, default: []].append(service)
        }
        return (order.sorted().map { ($0, buckets[$0] ?? []) }, uncategorised)
    }

    private var workers: [DeploymentNode] { deployment.nodes.filter(\.runsServices) }

    private func machineName(_ node: DeploymentNode) -> String {
        node.name.isEmpty ? node.endpoint.host : node.name
    }

    private func requestMove(_ service: ServiceID, to node: DeploymentNode) {
        let name = displayName(of: service)
        guard #available(macOS 15.0, *) else {
            moveRefusal = UIL10n.string("Agent management needs macOS 15 or newer.")
            return
        }
        guard !ServiceMoveCoordinator.isRunning(deployment: deployment.id) else { return }
        let movable = ServiceRegistry.service(service)
            .map { ServiceMovePolicy.isMovable($0, context: deployment.serviceContext) } ?? false
        guard movable else {
            moveRefusal = ServiceMoveWording.refusal(.notMovable(service), serviceName: name)
            return
        }
        switch deployment.moveRoute(of: service, to: node.id) {
        case .success(let route): pendingMove = route
        case .failure(let reason): moveRefusal = ServiceMoveWording.refusal(reason, serviceName: name)
        }
    }

    private var moveTitle: String {
        guard let route = pendingMove else { return "" }
        return UIL10n.string("Move %1$@ to %2$@?", displayName(of: route.service),
                             machineName(route.target))
    }

    private func startMove() {
        guard let route = pendingMove else { return }
        pendingMove = nil
        guard #available(macOS 15.0, *) else { return }
        launch(route: route, resuming: nil, undoOnly: false)
    }

    @available(macOS 15.0, *)
    private func launch(route: ServiceMoveRoute, resuming: ServiceMoveRecord?, undoOnly: Bool) {
        let coordinator = ServiceMoveCoordinator(
            deployment: deployment, route: route, resuming: resuming,
            onPlaced: { updated in
                deployment = updated
                onUpdate?(updated)
            },
            onSettled: { refreshInterruptedMove() })
        if undoOnly { coordinator?.putBack() } else { coordinator?.start() }
        interruptedMove = nil
    }

    private func refreshInterruptedMove() {
        guard #available(macOS 15.0, *), !ServiceMoveCoordinator.isRunning(deployment: deployment.id) else {
            interruptedMove = nil
            return
        }
        interruptedMove = ServiceMoveStore().record(for: deployment.id)
    }

    @ViewBuilder private var interruptedMoveSection: some View {
        if let record = interruptedMove, #available(macOS 15.0, *), onUpdate != nil {
            Section {
                Button("Continue the move") { resume(record, undoOnly: false) }
                    .rowActionButtonStyle()
                Button("Put it back") { resume(record, undoOnly: true) }
                    .rowActionButtonStyle()
            } header: {
                Text("A move did not finish")
            } footer: {
                Text(UIL10n.string("Moving %1$@ to %2$@ was interrupted.", displayName(of: record.service),
                                   machineName(record.target)))
            }
        }
    }

    private func resume(_ record: ServiceMoveRecord, undoOnly: Bool) {
        guard #available(macOS 15.0, *) else { return }
        switch deployment.moveRoute(of: record.service, to: record.target) {
        case .success(let route): launch(route: route, resuming: record, undoOnly: undoOnly)
        case .failure(let reason):
            moveRefusal = ServiceMoveWording.refusal(reason, serviceName: displayName(of: record.service))
        }
    }

    private func machineName(_ id: UUID) -> String {
        deployment.nodes.first { $0.id == id }.map(machineName) ?? ""
    }

    // MARK: - Wording

    private func title(for node: DeploymentNode) -> String {
        if !node.name.isEmpty { return node.name }
        if node.terminatesPublicTraffic && node.runsServices { return UIL10n.string("This server") }
        return node.terminatesPublicTraffic
            ? UIL10n.string("Entry server")
            : UIL10n.string("Services server")
    }

    private func role(of node: DeploymentNode) -> String {
        switch (node.terminatesPublicTraffic, node.runsServices) {
        case (true, true): return UIL10n.string("Answers publicly and runs the services")
        case (true, false): return UIL10n.string("Answers publicly, forwards to the other server")
        case (false, true): return UIL10n.string("Runs the services")
        case (false, false): return UIL10n.string("No role yet")
        }
    }

    private func explanation(for node: DeploymentNode) -> String {
        if node.terminatesPublicTraffic && !node.runsServices {
            return UIL10n.string("This server carries no services of its own. It holds the public address and forwards the deployment's ports to the server behind it.")
        }
        if node.servesOwnTraffic && !node.terminatesPublicTraffic {
            return UIL10n.string("Requests arrive here through the entry server's forwarded ports, and this machine answers them with its own certificate.")
        }
        return UIL10n.string("This machine answers on the public address and runs the services itself.")
    }

    private func delivery(of service: ServiceID) -> String {
        switch deployment.upstream(for: service, siteName: deployment.domain, placement: placement) {
        case .local: return UIL10n.string("Served here")
        case .mesh: return UIL10n.string("Proxied over the mesh")
        case nil: return UIL10n.string("Not placed")
        }
    }

    // MARK: - Data

    private func services(on node: DeploymentNode) -> [ServiceID] {
        let grouped = deployment.servicesByNode(placement: placement)
        return (grouped[node.id] ?? []).sorted { displayName(of: $0) < displayName(of: $1) }
    }

    private var unroutable: [ServiceID] {
        deployment.placementProblems(placement).map { problem in
            switch problem {
            case .needsMeshToReachWorker(let service): return service
            }
        }
    }

    private func displayName(of service: ServiceID) -> String {
        ServiceRegistry.all.first { $0.id == service }?.displayName ?? service.rawValue
    }
}

/// One shelf of this machine's services, folded away by default
private struct NodeServiceCategoryRow<Content: View>: View {
    let category: ServiceCategory
    let count: Int
    @ViewBuilder let content: () -> Content
    @AppStorage private var expanded: Bool

    init(storageKey: String, category: ServiceCategory, count: Int,
         @ViewBuilder content: @escaping () -> Content) {
        self.category = category
        self.count = count
        self.content = content
        _expanded = AppStorage(wrappedValue: false, storageKey)
    }

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expanded },
            set: { newValue in withAnimation(.smooth) { expanded = newValue } }
        )) {
            content()
        } label: {
            HStack(spacing: 6) {
                Label { Text(LocalizedStringKey(category.title)) } icon: { CategoryIcon(category: category) }
                Text(verbatim: "\(count)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
/// A way into this screen for the headless check
struct DeploymentNodesTarget: Hashable {
    let deployment: Deployment
}
#endif
