import Foundation

/// When and what the tunnel sends to its session card
public struct TunnelActivityFeed: Sendable {
    public struct Sample: Equatable, Sendable {
        public var received: Int64
        public var sent: Int64
        public var reconnecting: Bool

        public init(received: Int64, sent: Int64, reconnecting: Bool) {
            self.received = received
            self.sent = sent
            self.reconnecting = reconnecting
        }
    }

    public static let spacing: TimeInterval = 30
    public static let urgentSpacing: TimeInterval = 300

    private var lastSample: Sample?
    private var lastSent: Date?
    private var lastUrgent: Date?
    private var lastStamp = 0

    public init() {}

    /// The update to send now, or nil
    public mutating func next(_ sample: Sample, ticket: TunnelActivityTicket, now: Date) -> [String: Any]? {
        let statusChanged = lastSample.map { $0.reconnecting != sample.reconnecting } ?? true
        guard sample != lastSample else { return nil }
        if !statusChanged, let lastSent, now.timeIntervalSince(lastSent) < Self.spacing { return nil }
        let urgent = statusChanged || lastUrgent.map { now.timeIntervalSince($0) >= Self.urgentSpacing } ?? true
        lastSample = sample
        lastSent = now
        if urgent { lastUrgent = now }
        return ["state": Self.state(sample, ticket: ticket), "urgent": urgent, "timestamp": stamp(now)]
    }

    /// The last update: the card closes
    public mutating func end(_ sample: Sample, ticket: TunnelActivityTicket, now: Date) -> [String: Any] {
        var state = Self.state(sample, ticket: ticket)
        state["status"] = ["off": [String: Any]()]
        return ["end": true, "state": state, "dismiss_at": Int(now.timeIntervalSince1970),
                "timestamp": stamp(now)]
    }

    /// The app's ContentState, as JSON
    static func state(_ sample: Sample, ticket: TunnelActivityTicket) -> [String: Any] {
        let status = sample.reconnecting ? "reasserting" : "connected"
        return [
            "status": [status: ["since": ticket.since]],
            "statistics": ["received": sample.received, "sent": sample.sent],
        ]
    }

    private mutating func stamp(_ now: Date) -> Int {
        lastStamp = max(Int(now.timeIntervalSince1970), lastStamp + 1)
        return lastStamp
    }
}
