import Foundation

/// Caps how many agent RPCs are in flight at once
public actor AgentChannelGate {
    public static let defaultLimit = 4

    private let limit: Int
    private var active = 0
    private var waiters: [(id: UUID, resume: CheckedContinuation<Void, Never>)] = []

    public init(limit: Int = AgentChannelGate.defaultLimit) {
        self.limit = max(1, limit)
    }

    public static func shared(for deploymentID: UUID) -> AgentChannelGate {
        registryLock.lock()
        defer { registryLock.unlock() }
        if let existing = registry[deploymentID] { return existing }
        let gate = AgentChannelGate()
        registry[deploymentID] = gate
        return gate
    }

    private static let registryLock = NSLock()
    private nonisolated(unsafe) static var registry: [UUID: AgentChannelGate] = [:]

    public func withSlot<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await body()
    }

    private func acquire() async {
        if active < limit {
            active += 1
            return
        }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters.append((id, continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        active += 1
        waiter.resume.resume()
    }

    private func release() {
        if waiters.isEmpty {
            active -= 1
            return
        }
        let waiter = waiters.removeFirst()
        waiter.resume.resume()
    }
}
