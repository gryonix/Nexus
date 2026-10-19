import Foundation
import ServerControl

struct MetricPanel: Identifiable, Codable, Hashable {
    var id: UUID
    /// Which server
    var deploymentID: UUID
    var hostRaw: String
    /// One or more metrics, in catalog order
    var metricsRaw: [String]
    var rangeRaw: String

    init(id: UUID = UUID(), deploymentID: UUID, host: SSHHostID,
         metrics: [HistoryMetric], range: HistoryRange) {
        self.id = id
        self.deploymentID = deploymentID
        self.hostRaw = host.persistedRaw
        self.metricsRaw = metrics.map(\.rawValue)
        self.rangeRaw = range.rawValue
    }

    var host: SSHHostID { SSHHostID(persistedRaw: hostRaw) }
    var metrics: [HistoryMetric] {
        let decoded = metricsRaw.compactMap(HistoryMetric.init(rawValue:))
        return decoded.isEmpty ? [.cpu] : decoded
    }
    var metric: HistoryMetric { metrics[0] }
    var range: HistoryRange { HistoryRange(rawValue: rangeRaw) ?? .hour }

    /// What actually has to be fetched for this panel
    var source: Source { Source(deploymentID: deploymentID, hostRaw: hostRaw, bucket: range.bucket) }

    struct Source: Hashable {
        let deploymentID: UUID
        let hostRaw: String
        let bucket: MetricsHistoryBucket
        var host: SSHHostID { SSHHostID(persistedRaw: hostRaw) }

        /// From the raw string a panel already stores
        init(deploymentID: UUID, hostRaw: String, bucket: MetricsHistoryBucket) {
            self.deploymentID = deploymentID
            self.hostRaw = hostRaw
            self.bucket = bucket
        }

        init(deploymentID: UUID, host: SSHHostID, bucket: MetricsHistoryBucket) {
            self.init(deploymentID: deploymentID, hostRaw: host.persistedRaw, bucket: bucket)
        }
    }
}

/// The dashboard's panels, in the user's order
@MainActor
final class MetricPanelStore: ObservableObject {
    static let shared = MetricPanelStore()

    private static let key = "metrics.dashboardPanels"

    @Published private(set) var panels: [MetricPanel] = [] { didSet { schedulePersist() } }

    /// The pending write
    private var persistTask: Task<Void, Never>?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode([MetricPanel].self, from: data) {
            panels = stored
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_PANELS"] != nil,
           let demo = DemoDeployments.fromEnvironment() {
            let metrics: [[HistoryMetric]] = [[.network], [.cpu, .memory], [.disk],
                                              [.memory], [.load]]
            let ranges: [HistoryRange] = [.hour, .threeHours, .day, .hour, .tenHours]
            panels = demo.prefix(metrics.count).enumerated().map { index, deployment in
                MetricPanel(deploymentID: deployment.id, host: .vps,
                            metrics: metrics[index], range: ranges[index])
            }
        }
        #endif
    }

    func add(_ panel: MetricPanel) { panels.append(panel); flush() }

    /// Fills an empty board for the demo fleet
    func seedDemoBoardIfEmpty(for deployments: [Deployment]) {
        guard panels.isEmpty,
              !defaults.bool(forKey: Self.demoSeededKey),
              !deployments.isEmpty,
              deployments.allSatisfy({ DemoServer.isDemo($0) }) else { return }
        defaults.set(true, forKey: Self.demoSeededKey)
        let recipes: [(UUID, SSHHostID, [HistoryMetric], HistoryRange)] = [
            (DemoServer.id, .vps, [.cpu, .memory], .hour),
            (DemoServer.relayPairID, .vps, [.network], .day),
            (DemoServer.relayPairID, .home, [.cpu, .memory, .disk], .threeHours),
            (DemoServer.localOnlyID, .vps, [.disk], .week),
            (DemoServer.id, .vps, [.network], .tenHours),
            (DemoServer.sshOnlyID, .vps, [.load], .hour),
            (DemoServer.localOnlyID, .vps, [.temperature], .day),
            (DemoServer.id, .vps, [.diskIO], .threeHours)
        ]
        let known = Set(deployments.map(\.id))
        panels = recipes
            .filter { known.contains($0.0) }
            .map { MetricPanel(deploymentID: $0.0, host: $0.1, metrics: $0.2, range: $0.3) }
    }

    private static let demoSeededKey = "metrics.demoBoardSeeded"

    func remove(_ panel: MetricPanel) { panels.removeAll { $0.id == panel.id }; flush() }

    func reorder(_ ordered: [MetricPanel]) {
        defer { flush() }
        let ids = Set(ordered.map(\.id))
        let slots = panels.indices.filter { ids.contains(panels[$0].id) }
        guard slots.count == ordered.count else { return }
        for (slot, panel) in zip(slots, ordered) { panels[slot] = panel }
    }

    func replace(_ panel: MetricPanel) {
        guard let index = panels.firstIndex(where: { $0.id == panel.id }) else { return }
        panels[index] = panel
    }

    /// Drops panels whose server is gone
    func prune(against deployments: [Deployment]) {
        defer { flush() }
        let alive = Set(deployments.map(\.id))
        let kept = panels.filter { alive.contains($0.deploymentID) }
        if kept.count != panels.count { panels = kept }
    }

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    func flush() {
        persistTask?.cancel()
        persistTask = nil
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(panels) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
