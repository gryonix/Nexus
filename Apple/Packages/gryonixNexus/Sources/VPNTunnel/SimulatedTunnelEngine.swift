import Foundation

/// A tunnel that goes through every motion and carries nothing
public actor SimulatedTunnelEngine: TunnelEngine {
    public struct Timing: Sendable {
        public var handshake: Duration
        public var teardown: Duration
        public var tick: Duration

        public static let realistic = Timing(handshake: .milliseconds(900),
                                             teardown: .milliseconds(350),
                                             tick: .seconds(1))
        /// What a test sees
        public static let immediate = Timing(handshake: .milliseconds(1),
                                             teardown: .milliseconds(1),
                                             tick: .milliseconds(1))

        public init(handshake: Duration, teardown: Duration, tick: Duration) {
            self.handshake = handshake
            self.teardown = teardown
            self.tick = tick
        }
    }

    private let timing: Timing
    private let bytesPerTick: Int64

    private var current: TunnelEngineState = .idle
    private var listeners: [UUID: AsyncStream<TunnelEngineState>.Continuation] = [:]
    /// The task doing the pretending
    private var runner: Task<Void, Never>?

    private var failNextStart: String?

    public init(timing: Timing = .realistic, bytesPerTick: Int64 = 48_000) {
        self.timing = timing
        self.bytesPerTick = bytesPerTick
    }

    public func armFailure(_ reason: String) {
        failNextStart = reason
    }

    public func state() async -> TunnelEngineState { current }

    public nonisolated func events() -> AsyncStream<TunnelEngineState> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(id: id, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { await self.unregister(id: id) }
            }
        }
    }

    public func start(profile: TunnelProfile, secret: String) async throws {
        guard TunnelCapableProtocols.isIntegrated(profile.protocolID) else {
            throw TunnelEngineError.protocolNotCarried(profile.protocolID)
        }
        guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TunnelEngineError.configurationMissing
        }

        runner?.cancel()
        runner = nil
        publish(TunnelEngineState(status: .connecting, profileID: profile.id, statistics: .zero))

        let failure = failNextStart
        failNextStart = nil
        runner = Task { [weak self, timing, bytesPerTick] in
            guard let self else { return }
            do {
                try await Task.sleep(for: timing.handshake)
            } catch {
                return  // cancelled during the handshake: `stop` publishes the state
            }
            if let failure {
                await self.publish(TunnelEngineState(status: .failed(reason: failure),
                                                     profileID: profile.id,
                                                     statistics: .zero))
                return
            }
            let since = Date()
            await self.publish(TunnelEngineState(status: .connected(since: since),
                                                 profileID: profile.id,
                                                 statistics: TunnelStatistics(
                                                    received: 0, sent: 0, lastHandshake: since)))
            var ticks: Int64 = 0
            while !Task.isCancelled {
                do { try await Task.sleep(for: timing.tick) } catch { return }
                ticks += 1
                let statistics = TunnelStatistics(received: ticks * bytesPerTick,
                                                  sent: ticks * bytesPerTick / 3,
                                                  lastHandshake: since)
                await self.updateStatistics(statistics)
            }
        }
    }

    public func stop() async {
        runner?.cancel()
        runner = nil
        guard current.status != .off else { return }
        let statistics = current.statistics
        let profileID = current.profileID
        publish(TunnelEngineState(status: .disconnecting, profileID: profileID,
                                  statistics: statistics))
        try? await Task.sleep(for: timing.teardown)
        publish(TunnelEngineState(status: .off, profileID: profileID, statistics: statistics))
    }

    // MARK: - Fan-out

    private func register(id: UUID, continuation: AsyncStream<TunnelEngineState>.Continuation) {
        listeners[id] = continuation
        continuation.yield(current)
    }

    private func unregister(id: UUID) {
        listeners[id] = nil
    }

    private func updateStatistics(_ statistics: TunnelStatistics) {
        guard current.status.isActive else { return }
        publish(TunnelEngineState(status: current.status, profileID: current.profileID,
                                  statistics: statistics))
    }

    private func publish(_ state: TunnelEngineState) {
        current = state
        for continuation in listeners.values { continuation.yield(state) }
    }
}
