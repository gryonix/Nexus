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

    private let serverName: String
    /// Its agent moves the services machine's card
    private let deployment: Deployment?

    init(isDemo: Bool = false, serverName: String = "", deployment: Deployment? = nil,
         session: @escaping () async throws -> any SSHCommandRunner) {
        self.isDemo = isDemo
        self.serverName = serverName
        self.deployment = deployment
        self.session = session
    }

    deinit { polling?.cancel() }

    static func make(for viewModel: DashboardViewModel) -> SystemUpdateModel {
        SystemUpdateModel(isDemo: DemoFleet.covers(viewModel.deployment),
                          serverName: viewModel.deployment.name,
                          deployment: viewModel.deployment,
                          session: { [viewModel] in try await viewModel.commandSession() })
    }

    func load(_ hosts: [SSHHostID]) async {
        for host in hosts {
            await perform(host) { try await $0.status(on: host) }
            followIsland(host)
        }
        pollWhileRunning(hosts)
    }

    func start(_ host: SSHHostID, among hosts: [SSHHostID]) async {
        let agentHost = deployment.flatMap { $0.servicesHost == host && !isDemo ? $0 : nil }
        SystemUpdateIslands.runs[islandKey(host)] = IslandRun(title: UIL10n.string("Updating the system"), serverName: serverName,
                                  progressText: UIL10n.string("Starting…"),
                                  deployment: agentHost, jobID: agentHost == nil ? nil : Self.islandJob)
        await perform(host) { try await $0.start(on: host) }
        followIsland(host)
        pollWhileRunning(hosts)
    }

    /// The job the agent follows by the updater's log
    static let islandJob = "system-update"

    private func islandKey(_ host: SSHHostID) -> String {
        "\(deployment?.id.uuidString ?? serverName)|\(host)"
    }

    /// Mirrors one machine's run in its island card
    private func followIsland(_ host: SSHHostID) {
        guard let island = SystemUpdateIslands.runs[islandKey(host)] else { return }
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
        SystemUpdateIslands.runs[islandKey(host)] = nil
    }

    func setSwap(sizeGB: Int?, host: SSHHostID) async {
        await perform(host) { try await $0.setSwap(sizeGB: sizeGB, host: host) }
    }

    func setSchedule(_ schedule: CommandCatalog.Backups.Schedule, host: SSHHostID) async {
        await perform(host) { try await $0.setSchedule(schedule, host: host) }
    }

    func setRebootSchedule(_ schedule: RebootSchedule, host: SSHHostID) async {
        await perform(host, demoChange: { $0.rebootSchedule = schedule }) {
            try await $0.setRebootSchedule(schedule, host: host)
        }
    }

    func setAtStart(_ part: SystemUpdate.Part, on: Bool, host: SSHHostID) async {
        await perform(host) { try await $0.setAtStart(part, on: on, host: host) }
    }

    func setAtStop(_ part: SystemUpdate.Part, on: Bool, host: SSHHostID) async {
        await perform(host) { try await $0.setAtStop(part, on: on, host: host) }
    }

    private func perform(_ host: SSHHostID, demoChange: (inout SystemUpdateStatus) -> Void = { _ in },
                         _ work: (SystemUpdateOperations) async throws -> SystemUpdateStatus) async {
        busy.insert(host)
        defer { busy.remove(host) }
        if isDemo {
            var demo = Self.demo(statuses[host])
            demoChange(&demo)
            statuses[host] = demo
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
        status.rebootSchedule = previous?.rebootSchedule ?? .off
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

/// Island cards outlive the page that opened them
@MainActor
enum SystemUpdateIslands {
    static var runs: [String: IslandRun] = [:]
}
