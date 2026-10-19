import Foundation

public protocol MetricsHistoryReading: Sendable {
    func history(bucket: MetricsHistoryBucket, on host: SSHHostID) async throws -> [MetricsHistoryPoint]
}

public enum MetricsHistoryRouting {
    public static func route(usesAgent: Bool, agentTransportAvailable: Bool,
                             host: SSHHostID, agentHost: SSHHostID) -> ServiceControlRoute {
        guard host == agentHost else { return .ssh }
        return ServiceControlRouting.route(usesAgent: usesAgent,
                                           agentTransportAvailable: agentTransportAvailable)
    }
}

/// Reads one history bucket of one host over SSH
public struct MetricsHistoryProbe: MetricsHistoryReading, Sendable {
    private let runner: any SSHCommandRunner
    private let timeout: Duration

    public init(runner: any SSHCommandRunner, timeout: Duration = .seconds(15)) {
        self.runner = runner
        self.timeout = timeout
    }

    public func history(bucket: MetricsHistoryBucket,
                        on host: SSHHostID) async throws -> [MetricsHistoryPoint] {
        let command = CommandCatalog.metricsHistory(bucket: bucket)
        let result = try await runner.run(command, on: host, timeout: timeout)
        guard result.succeeded else {
            throw ServerControlError.commandFailure(command: command,
                                                    exitCode: result.exitCode,
                                                    stderr: result.stderr)
        }
        return MetricsHistoryParser.parse(result.stdout)
    }
}

/// Reads the per-filesystem history file over SSH
public struct DiskHistoryProbe: Sendable {
    private let runner: any SSHCommandRunner
    private let timeout: Duration

    public init(runner: any SSHCommandRunner, timeout: Duration = .seconds(15)) {
        self.runner = runner
        self.timeout = timeout
    }

    public func history(bucket: MetricsHistoryBucket, on host: SSHHostID) async throws -> [DiskHistoryPoint] {
        let result = try await runner.run(CommandCatalog.diskHistory(bucket: bucket), on: host, timeout: timeout)
        return DiskHistory.parse(result.stdout)
    }
}
