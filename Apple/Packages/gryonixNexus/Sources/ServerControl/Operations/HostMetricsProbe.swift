import Foundation

/// Fetches one `HostMetricsSample` over SSH
public struct HostMetricsProbe: Sendable {
    private let runner: any SSHCommandRunner
    private let timeout: Duration

    public init(runner: any SSHCommandRunner, timeout: Duration = .seconds(15)) {
        self.runner = runner
        self.timeout = timeout
    }

    public func sample(on host: SSHHostID) async throws -> HostMetricsSample {
        let result = try await runner.run(CommandCatalog.hostMetrics, on: host, timeout: timeout)
        guard result.succeeded else {
            throw ServerControlError.commandFailure(command: CommandCatalog.hostMetrics,
                                                    exitCode: result.exitCode,
                                                    stderr: result.stderr)
        }
        return try HostMetricsParser.parse(result.stdout)
    }
}
