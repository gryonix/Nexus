import Foundation
import VPNTunnel
@testable import gryonixNexus

@MainActor
final class RecordingTunnelActivity: TunnelActivityPresenting {
    enum Call: Equatable {
        case start(profileID: UUID, since: Date, isSimulated: Bool)
        case update(status: TunnelStatus)
        case end
    }

    private(set) var calls: [Call] = []

    var starts: Int { calls.filter { if case .start = $0 { return true } else { return false } }.count }
    var ends: Int { calls.filter { $0 == .end }.count }

    private(set) var styles: [VPNIslandStyle] = []
    private(set) var isStopArmed = false

    func start(profile: TunnelProfile, since: Date, isSimulated: Bool,
               statistics: TunnelStatistics, style: VPNIslandStyle) {
        calls.append(.start(profileID: profile.id, since: since, isSimulated: isSimulated))
        styles.append(style)
    }

    func setStopArmed(_ armed: Bool) {
        isStopArmed = armed
    }

    func update(status: TunnelStatus, statistics: TunnelStatistics) {
        calls.append(.update(status: status))
    }

    func end(statistics: TunnelStatistics) {
        calls.append(.end)
    }
}
