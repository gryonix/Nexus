import Foundation

/// Progress of the "restart everything" flow
public enum FullRestartEvent: Sendable, Hashable {
    case restartingService(name: String)
    case serviceRestarted(name: String)
    /// The service refused to restart
    case serviceFailed(name: String, detail: String)
    case restartSentToHomeTunnel
    case restartingVPSTunnel
    case vpsTunnelDone
    case waitingForTunnel(attempt: Int, maxAttempts: Int)
    case recovered
    case failedToRecover
}

public struct FullRestartOperation: Sendable {
    public static let pollInterval: Duration = .seconds(3)
    public static let maxPollAttempts = 20

    private let runner: any SSHCommandRunner
    private let config: DashboardConfig
    private let services: [ServiceRestartTarget]
    private let sleeper: any SleepProvider

    public struct ServiceRestartTarget: Sendable, Hashable {
        public let name: String
        public let command: String

        public init(name: String, command: String) {
            self.name = name
            self.command = command
        }
    }

    public init(runner: any SSHCommandRunner, config: DashboardConfig,
                services: [ServiceRestartTarget],
                sleeper: any SleepProvider = ContinuousClockSleeper()) {
        self.runner = runner
        self.config = config
        self.services = services
        self.sleeper = sleeper
    }

    public func run() -> AsyncThrowingStream<FullRestartEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for service in services {
                        continuation.yield(.restartingService(name: service.name))
                        let result = try? await runner.run(service.command, on: .home,
                                                           timeout: config.restartTimeout)
                        if let result, result.succeeded {
                            continuation.yield(.serviceRestarted(name: service.name))
                        } else {
                            let detail = result.map {
                                $0.stderr.isEmpty
                                    ? "exit \($0.exitCode.map(String.init) ?? "unknown")"
                                    : $0.stderr
                            } ?? "no answer"
                            continuation.yield(.serviceFailed(name: service.name, detail: detail))
                        }
                    }

                    let restart = CommandCatalog.restartWireGuard(interface: config.wgInterface)
                    try await runner.fireAndForget(restart, on: .home)
                    continuation.yield(.restartSentToHomeTunnel)

                    // 3. The VPS, reached directly rather than through the tunnel.
                    continuation.yield(.restartingVPSTunnel)
                    let vpsResult = try await runner.run(restart, on: .vps,
                                                         timeout: config.restartTimeout)
                    guard vpsResult.succeeded else {
                        throw ServerControlError.commandFailure(command: restart,
                                                                exitCode: vpsResult.exitCode,
                                                                stderr: vpsResult.stderr)
                    }
                    continuation.yield(.vpsTunnelDone)

                    // 4. Wait for the tunnel to re-form on its own.
                    let ping = CommandCatalog.pingTunnel(homeWGAddress: config.homeWGAddress)
                    for attempt in 1...Self.maxPollAttempts {
                        try await sleeper.sleep(for: Self.pollInterval)
                        continuation.yield(.waitingForTunnel(attempt: attempt,
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
