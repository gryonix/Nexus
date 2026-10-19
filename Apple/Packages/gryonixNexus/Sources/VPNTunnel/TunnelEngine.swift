import Foundation
import ServiceCatalog
import VPNProfile

public struct TunnelEngineState: Sendable, Equatable {
    public var status: TunnelStatus
    /// The profile the current (or last) session belongs to
    public var profileID: UUID?
    public var statistics: TunnelStatistics

    public static let idle = TunnelEngineState(status: .off, profileID: nil, statistics: .zero)

    public init(status: TunnelStatus, profileID: UUID?, statistics: TunnelStatistics) {
        self.status = status
        self.profileID = profileID
        self.statistics = statistics
    }
}

/// What actually brings a tunnel up
public protocol TunnelEngine: AnyObject, Sendable {
    /// Brings the profile up
    func start(profile: TunnelProfile, secret: String) async throws
    func stop() async
    func state() async -> TunnelEngineState
    func events() -> AsyncStream<TunnelEngineState>
}

/// Why a start could not even be attempted
public enum TunnelEngineError: Error, Equatable {
    case protocolNotCarried(ServiceID)
    case configurationUnreadable(WireGuardQuickConfig.ParseError?)
    /// The profile is here and its key is not
    case configurationMissing
    case systemRefused(String)
}

public enum TunnelAvailability {
    public enum Kind: Sendable {
        /// A real tunnel through the system's Network Extension
        case system
        /// A demonstration
        case simulated
    }

    public static var kind: Kind {
        #if GRYONIX_SYSTEM_TUNNEL && !targetEnvironment(simulator)
        return .system
        #else
        return .simulated
        #endif
    }

    /// Does switching this on actually route anything?
    public static var carriesTraffic: Bool { kind == .system }
}
