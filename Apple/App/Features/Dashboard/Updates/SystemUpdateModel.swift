import Foundation
import ServerControl

/// Package updates of each machine, polled while one runs
@MainActor
final class SystemUpdateModel: ObservableObject {
    @Published private(set) var statuses: [SSHHostID: SystemUpdateStatus] = [:]
    @Published private(set) var errors: [SSHHostID: String] = [:]
    @Published private(set) var missing: Set<SSHHostID> = []
    @Published private(set) var busy: Set<SSHHostID> = []

    private let session: () async throws -> any SSHCommandRunner
    private let isDemo: Bool
    private var polling: Task<Void, Never>?
    private var islands: [SSHHostID: IslandRun] = [:]

    private let serverName: String

    init(isDemo: Bool = false, serverName: String = "",
         session: @escaping () async throws -> any SSHCommandRunner) {
        self.isDemo = isDemo
        self.serverName = serverName
        self.session = session
    }

    deinit { polling?.cancel() }

    func load(_ hosts: [SSHHostID]) async {
        for host in hosts { await perform(host) { try await $0.status(on: host) } }
        pollWhileRunning(hosts)
    }

    func start(_ host: SSHHostID, among hosts: [SSHHostID]) async {
        islands[host] = IslandRun(title: UIL10n.string("Updating the system"), serverName: serverName,
                                  progressText: UIL10n.string("Starting…"))
        await perform(host) { try await $0.start(on: host) }
        followIsland(host)
        pollWhileRunning(hosts)
    }

    /// Mirrors one machine's run in its island card
    private func followIsland(_ host: SSHHostID) {
        guard let island = islands[host] else { return }
        if let error = errors[host] {
            island.finish("", error: error)
        } else if let status = statuses[host], status.isRunning {
            island.update(status.log.last ?? "")
            return
        } else if let status = statuses[host], (status.exitCode ?? 0) != 0 {
            island.finish("", error: status.log.last ?? UIL10n.string("The update failed."))
        } else {
            island.finish(UIL10n.string("The system is up to date."))
        }
        islands[host] = nil
    }

    func setSwap(sizeGB: Int?, host: SSHHostID) async {
        await perform(host) { try await $0.setSwap(sizeGB: sizeGB, host: host) }
    }

    func setSchedule(_ schedule: CommandCatalog.Backups.Schedule, host: SSHHostID) async {
        await perform(host) { try await $0.setSchedule(schedule, host: host) }
    }

    func setAtStart(_ part: SystemUpdate.Part, on: Bool, host: SSHHostID) async {
        await perform(host) { try await $0.setAtStart(part, on: on, host: host) }
    }

    func setAtStop(_ part: SystemUpdate.Part, on: Bool, host: SSHHostID) async {
        await perform(host) { try await $0.setAtStop(part, on: on, host: host) }
    }

    private func perform(_ host: SSHHostID,
                         _ work: (SystemUpdateOperations) async throws -> SystemUpdateStatus) async {
        busy.insert(host)
        defer { busy.remove(host) }
        if isDemo {
            statuses[host] = Self.demo(statuses[host])
            return
        }
        do {
            statuses[host] = try await work(SystemUpdateOperations(runner: session()))
            errors[host] = nil
            missing.remove(host)
        } catch SystemUpdateError.updaterMissing {
            missing.insert(host)
        } catch {
            errors[host] = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    /// A finished run; later calls finish it now
    private static func demo(_ previous: SystemUpdateStatus?) -> SystemUpdateStatus {
        var status = previous ?? SystemUpdateStatus()
        status.exitCode = 0
        status.finished = previous == nil ? Date(timeIntervalSinceNow: -2 * 86_400) : Date()
        status.log = ["0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded."]
        status.swapBytes = 2_147_483_648
        status.offersAtStop = true
        status.schedule = previous?.schedule ?? .off
        return status
    }

    private func pollWhileRunning(_ hosts: [SSHHostID]) {
        guard polling == nil, statuses.values.contains(where: \.isRunning) else { return }
        polling = Task { [weak self] in
            while let self, !Task.isCancelled, self.statuses.values.contains(where: \.isRunning) {
                try? await Task.sleep(for: .seconds(3))
                for host in hosts where self.statuses[host]?.isRunning == true {
                    await self.perform(host) { try await $0.status(on: host) }
                    self.followIsland(host)
                }
            }
            self?.polling = nil
        }
    }
}
