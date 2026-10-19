import AgentControl
import Foundation
import ServerControl
import ServerControlSSH
import SwiftUI

@MainActor
final class MetricsHistoryViewModel: ObservableObject {
    let deployment: Deployment
    let host: SSHHostID

    /// The selected look-back window
    @Published var range: HistoryRange = .hour {
        didSet { if oldValue != range { Task { await load() } } }
    }

    var bucket: MetricsHistoryBucket { range.bucket }
    @Published var points: [MetricsHistoryPoint] = []
    /// Each filesystem's use, for the disk chart's picker
    @Published var diskPoints: [DiskHistoryPoint] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var session: (any SSHCommandRunner)?
    private let makeSession: @Sendable () throws -> any SSHCommandRunner
    private var pollTask: Task<Void, Never>?

    init(deployment: Deployment, host: SSHHostID,
         makeSession: (@Sendable (Deployment) throws -> any SSHCommandRunner)? = nil) {
        self.deployment = deployment
        self.host = host
        let factory = makeSession ?? { try DashboardSessionFactory.makeRunner(deployment: $0) }
        self.makeSession = { try factory(deployment) }
    }

    func start() async {
        guard pollTask == nil else { return }
        await load()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.pollInterval ?? 60
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { break }
                await self.load()
            }
        }
    }

    private var pollInterval: TimeInterval {
        min(max(bucket.pointInterval / 4, 15), 60)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        if DemoHostMetrics.covers(deployment) {
            DemoHostMetrics.detectPower(deploymentID: deployment.id, host: host)
            points = EnergySettings.shared.filled(DemoHostMetrics.history(deploymentID: deployment.id,
                                                               host: host, bucket: bucket), deployment.id, host)
            diskPoints = DemoHostMetrics.diskHistory(points)
            errorMessage = nil
            return
        }
        do {
            let runner = try await connect()
            let loaded = try await historySource(runner: runner).history(bucket: bucket, on: host)
            await EnergySettings.shared.detect(deployment.id, host, runner: runner)
            let disks = DiskHistoryProbe(runner: runner, timeout: .seconds(deployment.timeouts.quickSeconds))
            diskPoints = (try? await disks.history(bucket: bucket, on: host)) ?? diskPoints
            points = EnergySettings.shared.filled(loaded, deployment.id, host)
            errorMessage = nil
        } catch {
            let stale = session
            session = nil
            let id = deployment.id
            Task.detached { await DashboardSessionFactory.release(stale, deploymentID: id) }
            if points.isEmpty {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            }
        }
    }

    /// Where this screen reads the collector's buckets from
    private func historySource(runner: any SSHCommandRunner) async -> any MetricsHistoryReading {
        let ssh = MetricsHistoryProbe(runner: runner,
                                      timeout: .seconds(deployment.timeouts.quickSeconds))
        guard #available(macOS 15.0, iOS 18.0, *) else { return ssh }
        let route = MetricsHistoryRouting.route(usesAgent: deployment.usesAgent,
                                                agentTransportAvailable: true,
                                                host: host,
                                                agentHost: deployment.servicesHost)
        guard route == .agent,
              let client = try? await AgentConnection.client(deployment: deployment, runner: runner)
        else { return ssh }
        return AgentMetricsHistory(client: client, gate: agentGate)
    }

    private lazy var agentGate = AgentChannelGate.shared(for: deployment.id)

    /// Any point carrying a temperature unlocks the temperature metric
    var hasTemperature: Bool {
        points.contains { $0.temperatureCelsius != nil }
    }

    func teardown() {
        pollTask?.cancel()
        pollTask = nil
        session = nil
    }

    private func connect() async throws -> any SSHCommandRunner {
        if let session { return session }
        let make = makeSession
        let fresh = try await Task.detached(priority: .userInitiated) { try make() }.value
        if let session {
            Task { [id = deployment.id] in
                await DashboardSessionFactory.release(fresh, deploymentID: id)
            }
            return session
        }
        session = fresh
        return fresh
    }
}
