import Foundation
import ServerControl

final class MetricsCache: @unchecked Sendable {
    static let shared = MetricsCache()

    private let url: URL
    private let lock = NSLock()
    private var entries: [String: [Point]]
    private static let pointLimit = 720

    init(directory: URL? = nil) {
        let root: URL
        if let directory {
            root = directory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first!
            root = support.appendingPathComponent("gryonixNexus", isDirectory: true)
        }
        url = root.appendingPathComponent("metrics-cache.json")
        entries = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode([String: [Point]].self, from: $0) } ?? [:]
    }

    // MARK: - Reading

    func points(for source: MetricPanel.Source) -> [MetricsHistoryPoint] {
        lock.lock()
        defer { lock.unlock() }
        return (entries[Self.key(source)] ?? []).map(\.point)
    }

    func latestPoint(deploymentID: UUID, host: SSHHostID) -> MetricsHistoryPoint? {
        let source = MetricPanel.Source(deploymentID: deploymentID,
                                        host: host,
                                        bucket: .tenSeconds)
        return points(for: source).last
    }

    // MARK: - Writing

    /// Records a successful read
    func store(_ points: [MetricsHistoryPoint], for source: MetricPanel.Source) {
        guard !points.isEmpty else { return }
        let trimmed = points.suffix(Self.pointLimit).map(Point.init)
        lock.lock()
        entries[Self.key(source)] = trimmed
        let snapshot = entries
        lock.unlock()
        persist(snapshot)
    }

    func prune(keeping deploymentIDs: Set<UUID>) {
        lock.lock()
        let kept = entries.filter { key, _ in
            guard let id = UUID(uuidString: String(key.prefix(36))) else { return false }
            return deploymentIDs.contains(id)
        }
        let changed = kept.count != entries.count
        entries = kept
        let snapshot = entries
        lock.unlock()
        guard changed else { return }
        persist(snapshot)
    }

    private func persist(_ snapshot: [String: [Point]]) {
        let url = url
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func key(_ source: MetricPanel.Source) -> String {
        "\(source.deploymentID.uuidString)-\(source.hostRaw)-\(source.bucket.rawValue)"
    }

    /// `MetricsHistoryPoint` on disk
    private struct Point: Codable {
        let t: Double
        let cpu: Double?
        let memUsed: Int64
        let memTotal: Int64
        let diskUsed: Int64
        let diskTotal: Int64
        let netRx: Double?
        let netTx: Double?
        let ioRead: Double?
        let ioWrite: Double?
        let load1: Double
        let temp: Double?

        init(_ point: MetricsHistoryPoint) {
            t = point.date.timeIntervalSince1970
            cpu = point.cpuPercent
            memUsed = point.memUsedBytes
            memTotal = point.memTotalBytes
            diskUsed = point.diskUsedBytes
            diskTotal = point.diskTotalBytes
            netRx = point.netReceivedPerSecond
            netTx = point.netSentPerSecond
            ioRead = point.diskReadPerSecond
            ioWrite = point.diskWrittenPerSecond
            load1 = point.load1
            temp = point.temperatureCelsius
        }

        var point: MetricsHistoryPoint {
            MetricsHistoryPoint(date: Date(timeIntervalSince1970: t),
                                cpuPercent: cpu,
                                memUsedBytes: memUsed, memTotalBytes: memTotal,
                                diskUsedBytes: diskUsed, diskTotalBytes: diskTotal,
                                netReceivedPerSecond: netRx, netSentPerSecond: netTx,
                                diskReadPerSecond: ioRead, diskWrittenPerSecond: ioWrite,
                                load1: load1, temperatureCelsius: temp)
        }
    }
}
