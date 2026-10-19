import Foundation

/// Progress of the "restart WireGuard on both machines" flow
public enum WGRestartEvent: Sendable, Hashable {
    case restartingVPS
    case vpsDone
    case restartSentToHome
    case pollingTunnel(attempt: Int, maxAttempts: Int)
    case recovered
    case failedToRecover
}

public struct WireGuardRestartOperation: Sendable {
    public static let pollInterval: Duration = .seconds(3)
    public static let maxPollAttempts = 20

    private let runner: any SSHCommandRunner
    private let config: DashboardConfig
    private let sleeper: any SleepProvider

    public init(runner: any SSHCommandRunner, config: DashboardConfig,
                sleeper: any SleepProvider = ContinuousClockSleeper()) {
        self.runner = runner
        self.config = config
        self.sleeper = sleeper
    }

    public func restartBoth() -> AsyncThrowingStream<WGRestartEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let restart = CommandCatalog.restartWireGuard(interface: config.wgInterface)

                    continuation.yield(.restartingVPS)
                    let vpsResult = try await runner.run(restart, on: .vps,
                                                         timeout: config.restartTimeout)
                    guard vpsResult.succeeded else {
                        throw ServerControlError.commandFailure(command: restart,
                                                                exitCode: vpsResult.exitCode,
                                                                stderr: vpsResult.stderr)
                    }
                    continuation.yield(.vpsDone)

                    try await runner.fireAndForget(restart, on: .home)
                    continuation.yield(.restartSentToHome)

                    let ping = CommandCatalog.pingTunnel(homeWGAddress: config.homeWGAddress)
                    for attempt in 1...Self.maxPollAttempts {
                        try await sleeper.sleep(for: Self.pollInterval)
                        continuation.yield(.pollingTunnel(attempt: attempt,
                                                          maxAttempts: Self.maxPollAttempts))
                        if let result = try? await runner.run(ping, on: .vps,
                                                              timeout: config.quickTimeout),
                           let parsed = try? PingParser.parse(result.stdout),
                           parsed.isAlive {
                            continuation.yield(.recovered)
                            continuation.finish()
                            return
                        }
                    }
                    continuation.yield(.failedToRecover)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
