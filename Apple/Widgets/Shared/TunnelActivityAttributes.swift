#if os(iOS)
import ActivityKit
import Foundation
import VPNTunnel

struct TunnelActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: TunnelStatus
        var statistics: TunnelStatistics
        /// The first tap on stop asks; the second one disconnects
        var stopArmed: Bool?
    }

    let profileName: String
    let serverName: String
    let protocolName: String
    let startedAt: Date
    let isSimulated: Bool
    var style: VPNIslandStyle?
}
#endif
