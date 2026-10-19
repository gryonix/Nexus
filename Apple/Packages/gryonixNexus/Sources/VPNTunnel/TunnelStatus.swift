import Foundation

/// Where a tunnel is, as one value
public enum TunnelStatus: Codable, Sendable, Hashable {
    case off
    case connecting
    case connected(since: Date)
    case reasserting(since: Date)
    case disconnecting
    case failed(reason: String)

    /// Is anything up?
    public var isActive: Bool {
        switch self {
        case .connected, .reasserting: return true
        case .off, .connecting, .disconnecting, .failed: return false
        }
    }

    public var isBusy: Bool {
        switch self {
        case .connecting, .disconnecting: return true
        case .off, .connected, .reasserting, .failed: return false
        }
    }

    /// When the current session began — `nil` unless one is up
    public var activeSince: Date? {
        switch self {
        case .connected(let since), .reasserting(let since): return since
        case .off, .connecting, .disconnecting, .failed: return nil
        }
    }

    public var failureReason: String? {
        if case .failed(let reason) = self { return reason }
        return nil
    }

    public var systemImage: String {
        switch self {
        case .off: return "lock.open"
        case .connecting, .disconnecting: return "lock.rotation"
        case .connected: return "lock.shield.fill"
        case .reasserting: return "lock.trianglebadge.exclamationmark"
        case .failed: return "exclamationmark.shield"
        }
    }
}

public struct TunnelStatistics: Codable, Sendable, Hashable {
    public var received: Int64
    public var sent: Int64
    /// WireGuard's own liveness signal
    public var lastHandshake: Date?

    public static let zero = TunnelStatistics(received: 0, sent: 0, lastHandshake: nil)

    public init(received: Int64 = 0, sent: Int64 = 0, lastHandshake: Date? = nil) {
        self.received = received
        self.sent = sent
        self.lastHandshake = lastHandshake
    }

    public var total: Int64 { received + sent }
}

/// One finished connection, for the log
public struct TunnelSession: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let profileID: UUID
    public let serverName: String
    public let protocolName: String
    public let deviceName: String
    public let startedAt: Date
    public var endedAt: Date?
    public var statistics: TunnelStatistics
    public var failureReason: String?
    public let wasSimulated: Bool

    public init(id: UUID = UUID(),
                profileID: UUID,
                serverName: String,
                protocolName: String,
                deviceName: String,
                startedAt: Date,
                endedAt: Date? = nil,
                statistics: TunnelStatistics = .zero,
                failureReason: String? = nil,
                wasSimulated: Bool) {
        self.id = id
        self.profileID = profileID
        self.serverName = serverName
        self.protocolName = protocolName
        self.deviceName = deviceName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.statistics = statistics
        self.failureReason = failureReason
        self.wasSimulated = wasSimulated
    }

    public static let interruptedMarker = "gryonix.session.interrupted"
    public static let stoppedByItselfMarker = "gryonix.session.stopped-by-itself"

    /// `nil` while it is still running
    public var duration: TimeInterval? {
        endedAt.map { $0.timeIntervalSince(startedAt) }
    }
}
