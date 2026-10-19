import Foundation
import VPNTunnel

/// A tunnel that goes exactly where a test puts it
final class FakeTunnelEngine: TunnelEngine, @unchecked Sendable {
    private(set) var started: [(profile: TunnelProfile, secret: String)] = []
    private(set) var stopCount = 0
    var startError: Error?

    private var current: TunnelEngineState = .idle
    private var continuations: [UUID: AsyncStream<TunnelEngineState>.Continuation] = [:]

    func start(profile: TunnelProfile, secret: String) async throws {
        if let startError { throw startError }
        started.append((profile, secret))
    }

    func stop() async { stopCount += 1 }

    private(set) var stateAsked = 0

    func state() async -> TunnelEngineState {
        stateAsked += 1
        return current
    }

    func events() -> AsyncStream<TunnelEngineState> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations[id] = nil }
            }
        }
    }

    func emit(_ state: TunnelEngineState) {
        current = state
        for continuation in continuations.values { continuation.yield(state) }
    }

    func emit(status: TunnelStatus, profile: TunnelProfile? = nil,
              statistics: TunnelStatistics = .zero) {
        emit(TunnelEngineState(status: status, profileID: profile?.id, statistics: statistics))
    }
}
