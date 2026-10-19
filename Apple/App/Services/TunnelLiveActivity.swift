import Foundation
import VPNTunnel

/// The lock-screen session, as the controller sees it
@MainActor
protocol TunnelActivityPresenting {
    func start(profile: TunnelProfile, since: Date, isSimulated: Bool,
               statistics: TunnelStatistics, style: VPNIslandStyle)
    func update(status: TunnelStatus, statistics: TunnelStatistics)
    func end(statistics: TunnelStatistics)
    var isStopArmed: Bool { get }
    func setStopArmed(_ armed: Bool)
}

/// What a Mac does about a lock-screen session: nothing
@MainActor
struct NoTunnelActivity: TunnelActivityPresenting {
    func start(profile: TunnelProfile, since: Date, isSimulated: Bool,
               statistics: TunnelStatistics, style: VPNIslandStyle) {}
    func update(status: TunnelStatus, statistics: TunnelStatistics) {}
    func end(statistics: TunnelStatistics) {}
    var isStopArmed: Bool { false }
    func setStopArmed(_ armed: Bool) {}
}

@MainActor
func makeTunnelActivityPresenter() -> any TunnelActivityPresenting {
    #if os(iOS)
    return TunnelLiveActivity()
    #else
    return NoTunnelActivity()
    #endif
}

#if os(iOS)
import ActivityKit

/// The lock-screen session, started and ended with the tunnel
@MainActor
final class TunnelLiveActivity: TunnelActivityPresenting {
    private var activity: Activity<TunnelActivityAttributes>?
    private var tokenWatch: Task<Void, Never>?
    private(set) var isStopArmed = false
    private var lastStatus: TunnelStatus = .off
    private var lastStatistics = TunnelStatistics.zero

    func start(profile: TunnelProfile, since: Date, isSimulated: Bool,
               statistics: TunnelStatistics, style: VPNIslandStyle) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end(statistics: statistics)
        Self.endLeftovers()
        let attributes = TunnelActivityAttributes(profileName: profile.deviceName,
                                                  serverName: profile.serverName,
                                                  protocolName: profile.protocolID.displayName,
                                                  startedAt: since,
                                                  isSimulated: isSimulated,
                                                  style: style)
        let state = TunnelActivityAttributes.ContentState(status: .connected(since: since),
                                                          statistics: statistics)
        activity = Self.request(attributes, content: ActivityContent(state: state, staleDate: nil))
        if let activity, !isSimulated { followPushToken(of: activity, profile: profile, since: since) }
    }

    /// Ends sessions this launch did not start
    private static func endLeftovers() {
        for leftover in Activity<TunnelActivityAttributes>.activities {
            Task { await leftover.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Asks for a push token, falls back to local updates
    private static func request(_ attributes: TunnelActivityAttributes,
                                content: ActivityContent<TunnelActivityAttributes.ContentState>)
        -> Activity<TunnelActivityAttributes>? {
        if let pushed = try? Activity.request(attributes: attributes, content: content, pushType: .token) {
            return pushed
        }
        return try? Activity.request(attributes: attributes, content: content)
    }

    private func followPushToken(of activity: Activity<TunnelActivityAttributes>,
                                 profile: TunnelProfile, since: Date) {
        tokenWatch = Task {
            for await data in activity.pushTokenUpdates {
                let token = data.map { String(format: "%02x", $0) }.joined()
                TunnelActivityPush.shared.tokenArrived(token, profile: profile, since: since)
            }
        }
    }

    func update(status: TunnelStatus, statistics: TunnelStatistics) {
        lastStatus = status
        lastStatistics = statistics
        guard let activity else { return }
        let state = TunnelActivityAttributes.ContentState(status: status, statistics: statistics,
                                                          stopArmed: isStopArmed ? true : nil)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func setStopArmed(_ armed: Bool) {
        isStopArmed = armed
        guard let activity else { return }
        var state = activity.content.state
        state.stopArmed = armed ? true : nil
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end(statistics: TunnelStatistics) {
        tokenWatch?.cancel()
        tokenWatch = nil
        TunnelActivityPush.shared.stop()
        isStopArmed = false
        guard let activity else { return }
        self.activity = nil
        let state = TunnelActivityAttributes.ContentState(status: .off, statistics: statistics)
        Task {
            await activity.end(ActivityContent(state: state, staleDate: nil),
                               dismissalPolicy: .immediate)
        }
    }
}
#endif
