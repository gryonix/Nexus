import Foundation

/// The last N connections, oldest dropped
public struct TunnelSessionLog: Sendable {
    public static let capacity = 500

    private let file: SharedJSONFile<[TunnelSession]>
    private let capacity: Int

    public init(capacity: Int = TunnelSessionLog.capacity) {
        self.file = SharedJSONFile(name: "vpn-sessions.json")
        self.capacity = capacity
    }

    public init(fileURL: URL, capacity: Int = TunnelSessionLog.capacity) {
        self.file = SharedJSONFile(url: fileURL)
        self.capacity = capacity
    }

    /// Newest first — the order every screen shows them in
    public func sessions() -> [TunnelSession] {
        (file.read() ?? []).sorted { $0.startedAt > $1.startedAt }
    }

    /// The one that has not ended, if any
    public func running() -> TunnelSession? {
        sessions().first { $0.endedAt == nil }
    }

    @discardableResult
    public func begin(_ session: TunnelSession) -> TunnelSession {
        var stored = file.read() ?? []
        for index in stored.indices where stored[index].endedAt == nil {
            stored[index].endedAt = stored[index].startedAt
            stored[index].failureReason = TunnelSession.interruptedMarker
        }
        stored.append(session)
        write(stored)
        return session
    }

    public func end(id: UUID, at date: Date = Date(),
                    statistics: TunnelStatistics, failureReason: String? = nil) {
        var stored = file.read() ?? []
        guard let index = stored.firstIndex(where: { $0.id == id && $0.endedAt == nil }) else {
            return
        }
        stored[index].endedAt = date
        stored[index].statistics = statistics
        stored[index].failureReason = failureReason
        write(stored)
    }

    public func update(id: UUID, statistics: TunnelStatistics) {
        var stored = file.read() ?? []
        guard let index = stored.firstIndex(where: { $0.id == id && $0.endedAt == nil }) else {
            return
        }
        stored[index].statistics = statistics
        write(stored)
    }

    public func total(since: Date) -> TunnelStatistics {
        sessions()
            .filter { ($0.endedAt ?? Date()) >= since }
            .reduce(into: TunnelStatistics.zero) { total, session in
                total.received += session.statistics.received
                total.sent += session.statistics.sent
            }
    }

    public func clear() {
        file.write([])
    }

    private func write(_ sessions: [TunnelSession]) {
        let trimmed = sessions.count > capacity
            ? Array(sessions.suffix(capacity))
            : sessions
        file.write(trimmed)
    }
}
