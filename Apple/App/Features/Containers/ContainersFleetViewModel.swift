import AgentControl
import Foundation
import ServerControl
import ServerControlSSH
import SwiftUI

@available(macOS 15.0, *)
@MainActor
final class ContainersFleetViewModel: ObservableObject {
    /// The fleet-wide section's own model, kept alive between visits
    static let shared = ContainersFleetViewModel()

    static func forServer(_ deploymentID: UUID) -> ContainersFleetViewModel {
        if let existing = perServer[deploymentID] { return existing }
        let fresh = ContainersFleetViewModel()
        perServer[deploymentID] = fresh
        return fresh
    }

    private static var perServer: [UUID: ContainersFleetViewModel] = [:]

    static func forget(deploymentID: UUID) {
        perServer.removeValue(forKey: deploymentID)
    }

    /// One server's answer
    enum ServerState {
        case loading
        /// The host answered
        case loaded(ContainerInventory)
        case failed(String)
        /// The server has no agent, so nothing can ask it
        case needsAgent
    }

    @Published private(set) var states: [UUID: ServerState] = [:]
    @Published private(set) var isRefreshing = false

    private var known: [UUID: Deployment] = [:]

    func load(_ deployments: [Deployment]) async {
        isRefreshing = true
        defer { isRefreshing = false }
        for deployment in deployments { known[deployment.id] = deployment }
        await withTaskGroup(of: (UUID, ServerState).self) { group in
            for deployment in deployments {
                group.addTask { [weak self] in
                    guard let self else { return (deployment.id, .needsAgent) }
                    return (deployment.id, await self.state(for: deployment))
                }
            }
            for await (id, state) in group {
                states[id] = state
            }
            let live = Set(deployments.map(\.id))
            states = states.filter { live.contains($0.key) }
            known = known.filter { live.contains($0.key) }
        }
    }

    private func state(for deployment: Deployment) async -> ServerState {
        guard deployment.usesAgent || DemoFleet.covers(deployment) else { return .needsAgent }
        do {
            return .loaded(try await operations(for: deployment).inventory())
        } catch {
            return .failed(DashboardViewModel.message(for: error))
        }
    }

    func summary(for deploymentID: UUID) -> String {
        switch states[deploymentID] {
        case .loaded(let inventory) where inventory.unavailableReason == nil:
            return "\(inventory.groups.count)"
        default:
            return "—"
        }
    }

    func rename(_ key: String, to name: String, on deployment: Deployment) async {
        await apply(deployment) { try await $0.rename(key: key, to: name) }
    }

    func control(_ key: String, action: ContainerAction, on deployment: Deployment) async {
        do {
            try await operations(for: deployment).control(key: key, action: action)
        } catch {
            states[deployment.id] = .failed(DashboardViewModel.message(for: error))
            return
        }
        await apply(deployment) { try await $0.inventory() }
    }

    /// Loads one container's detail
    func detail(for name: String, on deployment: Deployment) async throws -> ContainerDetail {
        try await operations(for: deployment).inspect(container: name)
    }

    func backupPlan(for key: String, on deployment: Deployment) async throws -> ContainerBackupPlan {
        try await operations(for: deployment).backupPlan(key: key)
    }

    @discardableResult
    func setBackupPlan(_ plan: ContainerBackupPlan?, for key: String,
                       on deployment: Deployment) async throws -> ContainerBackupPlan {
        try await operations(for: deployment).setBackupPlan(key: key, plan: plan)
    }

    func logs(for key: String, on deployment: Deployment) async throws
    -> AsyncThrowingStream<ContainerLogLine, Error> {
        try await operations(for: deployment).logs(key: key, tail: 200)
    }

    func runBackup(for key: String, on deployment: Deployment,
                   onLine: @escaping @Sendable (String) -> Void) async throws -> ContainerArchive? {
        try await operations(for: deployment).runBackup(key: key, onLine: onLine)
    }

    func removalPreview(for key: String, on deployment: Deployment,
                        purgeData: Bool, purgeBackups: Bool) async throws -> ContainerRemovalPreview {
        try await operations(for: deployment).removalPreview(key: key, purgeData: purgeData,
                                                             purgeBackups: purgeBackups)
    }

    /// Removes, then RE-READS — never patches the listing from the stream
    func remove(_ key: String, on deployment: Deployment, purgeData: Bool, purgeBackups: Bool,
                onLine: @escaping @Sendable (String) -> Void) async throws {
        defer { Task { await apply(deployment) { try await $0.inventory() } } }
        try await operations(for: deployment).remove(key: key, purgeData: purgeData,
                                                     purgeBackups: purgeBackups, onLine: onLine)
    }

    func update(_ key: String, on deployment: Deployment, skipBackup: Bool = false,
                onLine: @escaping @Sendable (String) -> Void) async throws -> ContainerUpdateOutcome {
        defer { Task { await apply(deployment) { try await $0.inventory() } } }
        return try await operations(for: deployment).update(key: key, skipBackup: skipBackup,
                                                            onLine: onLine)
    }

    func backupSchedule(for key: String, on deployment: Deployment) async throws -> ContainerBackupSchedule {
        try await operations(for: deployment).backupSchedule(key: key)
    }

    @discardableResult
    func setBackupSchedule(_ cadence: ContainerBackupCadence?, for key: String,
                           on deployment: Deployment) async throws -> ContainerBackupSchedule {
        try await operations(for: deployment).setBackupSchedule(key: key, every: cadence)
    }

    /// The archives this group's backups have left, newest first
    func backups(for key: String, on deployment: Deployment) async throws -> ContainerBackupListing {
        try await operations(for: deployment).backups(key: key)
    }

    private func apply(_ deployment: Deployment,
                       _ call: (any ContainerManaging) async throws -> ContainerInventory) async {
        do {
            states[deployment.id] = .loaded(try await call(try await operations(for: deployment)))
        } catch {
            states[deployment.id] = .failed(DashboardViewModel.message(for: error))
        }
    }

    private func operations(for deployment: Deployment) async throws -> any ContainerManaging {
        let runner = try await DashboardSessionFactory.makeRunnerDetached(deployment: deployment)
        let client = try await AgentConnection.client(deployment: deployment, runner: runner)
        return AgentContainerOperations(client: client,
                                        gate: AgentChannelGate.shared(for: deployment.id))
    }
}
