import AgentControl
import Foundation
import ServerControl
import ServerControlSSH
import SwiftUI

@MainActor
final class MetricsDashboardViewModel: ObservableObject {
    @Published private(set) var points: [MetricPanel.Source: [MetricsHistoryPoint]] = [:]
    @Published private(set) var errors: [UUID: String] = [:]
    @Published private(set) var isLoading = false

    private var sessions: [UUID: any SSHCommandRunner] = [:]
    private var pollTask: Task<Void, Never>?
    private var deployments: [UUID: Deployment] = [:]
    private var sources: Set<MetricPanel.Source> = []

    private let makeSession: @Sendable (Deployment) throws -> any SSHCommandRunner

    init(makeSession: (@Sendable (Deployment) throws -> any SSHCommandRunner)? = nil) {
        self.makeSession = makeSession ?? { try DashboardSessionFactory.makeRunner(deployment: $0) }
    }

    /// Called whenever the panel list or the server list changes
    func update(panels: [MetricPanel], deployments: [Deployment]) {
        self.deployments = Dictionary(uniqueKeysWithValues: deployments.map { ($0.id, $0) })
        let wanted = Set(panels.map(\.source))
        guard wanted != sources || pollTask == nil else { return }
        sources = wanted
        let live = Set(wanted.map(\.deploymentID))
        for id in sessions.keys where !live.contains(id) {
            sessions.removeValue(forKey: id)
        }
        points = points.filter { wanted.contains($0.key) }
        for source in wanted where points[source] == nil {
            let cached = MetricsCache.shared.points(for: source)
            if !cached.isEmpty { points[source] = cached }
        }
        startPolling()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.load()
                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func load() async {
        guard !sources.isEmpty else { return }
        isLoading = points.isEmpty
        defer { isLoading = false }
        await withTaskGroup(of: (MetricPanel.Source, Result<[MetricsHistoryPoint], Error>)?.self) { group in
            for source in sources {
                guard let deployment = deployments[source.deploymentID] else { continue }
                if DemoHostMetrics.covers(deployment) {
                    points[source] = EnergySettings.shared.filled(DemoHostMetrics.history(deploymentID: deployment.id,
                                                host: source.host, bucket: source.bucket), deployment.id, source.host)
                    errors[deployment.id] = nil
                    continue
                }
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    do {
                        let runner = try await self.session(for: deployment)
                        let reader = await self.historySource(deployment: deployment,
                                                              host: source.host, runner: runner)
                        return (source, .success(try await reader.history(bucket: source.bucket,
                                                                          on: source.host)))
                    } catch {
                        return (source, .failure(error))
                    }
                }
            }
            for await answer in group {
                guard let (source, result) = answer,
                      let deployment = deployments[source.deploymentID] else { continue }
                switch result {
                case .success(let read):
                    let filled = EnergySettings.shared.filled(read, deployment.id, source.host)
                    points[source] = filled
                    errors[deployment.id] = nil
                    MetricsCache.shared.store(filled, for: source)
                case .failure(let error):
                    sessions.removeValue(forKey: deployment.id)
                    if points[source]?.isEmpty ?? true {
                        errors[deployment.id] = (error as? LocalizedError)?.errorDescription
                            ?? String(describing: error)
                    }
                }
            }
        }
    }

    /// Pull-to-refresh: rebuild the connection, then read again
    func reconnect() async {
        let servers = Set(sources.map(\.deploymentID))
        sessions.removeAll()
        for id in servers { DashboardSessionFactory.invalidate(deploymentID: id) }
        await load()
    }

    func teardown() {
        pollTask?.cancel()
        pollTask = nil
        sessions.removeAll()
    }

    private func session(for deployment: Deployment) async throws -> any SSHCommandRunner {
        if let existing = sessions[deployment.id] { return existing }
        let make = makeSession
        let fresh = try await Task.detached(priority: .userInitiated) {
            try make(deployment)
        }.value
        if let raced = sessions[deployment.id] {
            Task { await DashboardSessionFactory.release(fresh, deploymentID: deployment.id) }
            return raced
        }
        sessions[deployment.id] = fresh
        return fresh
    }

    private func historySource(deployment: Deployment, host: SSHHostID,
                               runner: any SSHCommandRunner) async -> any MetricsHistoryReading {
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
        return AgentMetricsHistory(client: client, gate: .shared(for: deployment.id))
    }
}
