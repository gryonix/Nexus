import Foundation
import ServerControl
import AgentControl
import ServiceCatalog

/// Backups of one server and its drives
@MainActor
final class ServerBackupsModel: ObservableObject {
    @Published private(set) var rows: [FleetBackup] = []
    /// Why this server did not list its backups
    @Published private(set) var failure: String?
    /// Why the last delete did not go through
    @Published private(set) var actionError: String?
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false

    let dashboard: DashboardViewModel
    /// Every server, for restoring onto another one
    let fleet: @MainActor () -> [Deployment]
    let makeDashboard: @MainActor (Deployment) -> DashboardViewModel
    private var generation = 0
    private let deadline: Duration
    private let lister: Lister?

    /// Asks the server for its backups, reporting partial answers
    typealias Lister = @MainActor (@escaping @MainActor (ServerBackups) -> Void) async -> ServerBackups

    init(dashboard: DashboardViewModel, deadline: Duration = .seconds(20), lister: Lister? = nil,
         fleet: @escaping @MainActor () -> [Deployment] = ServerBackupsModel.storedFleet,
         makeDashboard: @escaping @MainActor (Deployment) -> DashboardViewModel = { DashboardViewModel(deployment: $0) }) {
        self.dashboard = dashboard
        self.deadline = deadline
        self.lister = lister
        self.fleet = fleet
        self.makeDashboard = makeDashboard
    }

    private static func storedFleet() -> [Deployment] {
        #if DEBUG
        if let demo = DemoDeployments.fromEnvironment() { return demo }
        #endif
        return (try? FileDeploymentStore().load()) ?? []
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        generation += 1
        let round = generation
        failure = nil
        let dashboard = self.dashboard
        let list = lister ?? { progress in await dashboard.serverBackups(progress: progress) }
        let timedOut = ServerBackups(failed: true, reason: UIL10n.string("The server did not answer."))
        let result = await Deadline.run(deadline, fallback: timedOut) {
            await list { partial in self.accept(partial, round: round) }
        }
        accept(result, round: round, done: true)
        isLoading = false
        hasLoaded = true
    }

    private func accept(_ result: ServerBackups, round: Int, done: Bool = false) {
        guard round == generation else { return }
        if !(result.failed && result.rows.isEmpty && done) { rows = BackupOverview.sorted(result.rows) }
        if done { failure = result.failed ? result.reason : nil }
    }

    /// Deletes each backup, then reads the list again
    func deleteMany(_ rows: [FleetBackup]) async {
        actionError = nil
        for row in rows {
            guard let service = service(of: row) else { continue }
            do {
                let (operations, _) = try await dashboard.operations(for: service)
                guard let path = operations.backupPath(for: row.entry) else { continue }
                try await dashboard.backupSeam(for: service).deleteBackup(service, path: path)
            } catch {
                actionError = actionError ?? DashboardViewModel.message(for: error)
            }
        }
        await load()
    }

    /// Copies the backups here so they can be shared
    func downloadMany(_ rows: [FleetBackup]) async throws -> [URL] {
        var urls: [URL] = []
        for row in rows {
            guard let service = service(of: row), let path = dashboard.backupPath(service, entry: row.entry)
            else { continue }
            let dashboard = self.dashboard
            urls.append(try await BackupSharing.stage(path: path) { try await dashboard.downloadBackup(service, at: $0) })
        }
        return urls
    }

    func canDelete(_ row: FleetBackup) -> Bool {
        guard let service = service(of: row) else { return false }
        return dashboard.backupPath(service, entry: row.entry) != nil
    }

    /// Only archives on this server can be downloaded
    func canShare(_ row: FleetBackup) -> Bool {
        row.entry.drive == nil && !row.entry.isDirectory && canDelete(row)
    }

    private func service(of row: FleetBackup) -> (any ManagedService)? {
        dashboard.services.first { $0.id.rawValue == row.serviceID }
    }
}

/// One server's backups and whether it answered
struct ServerBackups {
    var rows: [FleetBackup] = []
    var failed = false
    var reason: String?
}

extension DashboardViewModel {
    /// Backups of every service, in one agent call if possible
    func serverBackups(progress: @escaping @MainActor (ServerBackups) -> Void) async -> ServerBackups {
        var result = ServerBackups()
        var remaining = services.filter { $0.actions(deployment.serviceContext).backup != nil }
        if let agent = await agentBackups(), let all = try? await agent.listAll() {
            result.rows = fleetRows(from: all, covering: &remaining)
            progress(result)
        }
        await withTaskGroup(of: ServerBackups.self) { group in
            var seen = Set<String>()
            for service in remaining where seen.insert(Self.listingKey(service)).inserted {
                group.addTask { @MainActor in await self.serverBackups(of: service) }
            }
            for await part in group {
                result.rows += part.rows
                result.failed = result.failed || part.failed
                result.reason = result.reason ?? part.reason
                progress(result)
            }
        }
        return result
    }

    private static func listingKey(_ service: any ManagedService) -> String {
        AgentServiceMapping.agentID(for: service.id) ?? service.id.rawValue
    }

    /// Rows for services the agent listed; others stay
    private func fleetRows(from all: [String: [BackupEntry]],
                           covering remaining: inout [any ManagedService]) -> [FleetBackup] {
        var rows: [FleetBackup] = []
        var covered = Set<String>()
        remaining.removeAll { service in
            guard let id = AgentServiceMapping.agentID(for: service.id), let entries = all[id] else { return false }
            if covered.insert(id).inserted {
                rows += entries.map { fleetRow($0, service: service) }
            }
            return true
        }
        return rows
    }

    private func fleetRow(_ entry: BackupEntry, service: any ManagedService) -> FleetBackup {
        FleetBackup(serverID: deployment.id, serverName: deployment.name,
                    serviceID: service.id.rawValue, serviceName: service.displayName, entry: entry)
    }

    private func serverBackups(of service: any ManagedService) async -> ServerBackups {
        do {
            let entries = try await backupSeam(for: service).listBackups(of: service)
            return ServerBackups(rows: entries.map { fleetRow($0, service: service) })
        } catch {
            return ServerBackups(failed: true, reason: Self.message(for: error))
        }
    }
}
