import AgentClient
import Foundation
import ServerControl

public struct AgentMetricsHistory: MetricsHistoryReading {
    private let client: AgentClient
    private let gate: AgentChannelGate?
    private let window: TimeInterval?

    public init(client: AgentClient, gate: AgentChannelGate? = nil, window: TimeInterval? = nil) {
        self.client = client
        self.gate = gate
        self.window = window
    }

    public func history(bucket: MetricsHistoryBucket, on host: SSHHostID) async throws -> [MetricsHistoryPoint] {
        let since = window.map { Date().addingTimeInterval(-$0) }
        let response = try await withSlot {
            try await client.metricsHistory(bucket: bucket.rawValue, since: since)
        }
        return response.points.map(MetricsHistoryPoint.init(agent:))
    }

    private func withSlot<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        guard let gate else { return try await body() }
        return try await gate.withSlot(body)
    }
}

extension MetricsHistoryPoint {
    /// The agent's point in the shape the chart already reads
    init(agent point: Gryonixnexusd_V1_MetricsHistoryPoint) {
        self.init(
            date: Date(timeIntervalSince1970: Double(point.at) / 1000),
            cpuPercent: point.hasCpuPercent ? point.cpuPercent : nil,
            memUsedBytes: point.memUsedBytes,
            memTotalBytes: point.memTotalBytes,
            diskUsedBytes: point.diskUsedBytes,
            diskTotalBytes: point.diskTotalBytes,
            netReceivedPerSecond: point.hasNetReceivedPerSecond ? point.netReceivedPerSecond : nil,
            netSentPerSecond: point.hasNetSentPerSecond ? point.netSentPerSecond : nil,
            diskReadPerSecond: point.hasDiskReadPerSecond ? point.diskReadPerSecond : nil,
            diskWrittenPerSecond: point.hasDiskWrittenPerSecond ? point.diskWrittenPerSecond : nil,
            load1: point.load1,
            temperatureCelsius: point.hasTemperatureCelsius ? point.temperatureCelsius : nil,
            powerWatts: point.hasPowerWatts ? point.powerWatts : nil,
            powerSource: point.powerSource.isEmpty ? nil : point.powerSource
        )
    }
}
