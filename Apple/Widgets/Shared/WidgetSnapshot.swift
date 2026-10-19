import Foundation
import ServiceCatalog
import VPNTunnel
import WidgetKit

/// What a widget draws, and where it comes from
struct TunnelEntry: TimelineEntry {
    let date: Date
    let snapshot: FleetSnapshot?
    var isPlaceholder = false

    var value: FleetSnapshot { snapshot ?? .placeholder }

    var available: Bool { snapshot != nil }
}

extension FleetSnapshot {
    /// The gallery's stand-in
    static var placeholder: FleetSnapshot {
        FleetSnapshot(
            generatedAt: Date().addingTimeInterval(-240),
            servers: [
                .init(id: UUID(), name: "Home server",
                      protocols: [.init(protocolID: .wireguardVPN, deviceCount: 3,
                                        deviceNames: ["iPhone", "MacBook", "iPad"]),
                                  .init(protocolID: .amneziaWG, deviceCount: 1,
                                        deviceNames: ["iPhone (obfuscated)"])],
                      metrics: .init(cpuPercent: 37,
                                     memUsedBytes: 5_100_000_000,
                                     memTotalBytes: 8_000_000_000,
                                     diskUsedBytes: 41_000_000_000,
                                     diskTotalBytes: 80_000_000_000,
                                     machineLabel: "Local",
                                     takenAt: Date().addingTimeInterval(-240)),
                      services: .init(total: 9, needingAttention: 1,
                                      takenAt: Date().addingTimeInterval(-240)),
                      security: .init(isPresent: true, engineRunning: true,
                                      bouncerRunning: true, alertsLast24h: 31,
                                      localBans: 4, communityBlocklistIPs: 15_737,
                                      takenAt: Date().addingTimeInterval(-240)),
                      backups: .init(isOn: true, everyDays: 1, servicesCovered: 6,
                                     retention: 7,
                                     takenAt: Date().addingTimeInterval(-240)),
                      updates: .init(waiting: 2, checked: 9,
                                     lastRunOnServer: Date().addingTimeInterval(-7_200),
                                     takenAt: Date().addingTimeInterval(-240))),
                .init(id: UUID(), name: "Relay",
                      protocols: [.init(protocolID: .wireguardVPN, deviceCount: 2,
                                        deviceNames: ["Work laptop", "Router"])],
                      metrics: .init(cpuPercent: 8,
                                     memUsedBytes: 900_000_000,
                                     memTotalBytes: 2_000_000_000,
                                     diskUsedBytes: 12_000_000_000,
                                     diskTotalBytes: 25_000_000_000,
                                     machineLabel: "VPS",
                                     takenAt: Date().addingTimeInterval(-95)),
                      services: .init(total: 3, needingAttention: 0,
                                      takenAt: Date().addingTimeInterval(-95)),
                      backups: .init(isOn: true, everyDays: 1, servicesCovered: 3,
                                     retention: 7,
                                     takenAt: Date().addingTimeInterval(-95)),
                      updates: .init(waiting: 0, checked: 3,
                                     lastRunOnServer: Date().addingTimeInterval(-3_600),
                                     takenAt: Date().addingTimeInterval(-95)))
            ],
            tunnel: TunnelSnapshot(status: .connected(since: Date().addingTimeInterval(-3_725)),
                                   profileName: "iPhone",
                                   serverName: "Home server",
                                   protocolName: "WireGuard",
                                   statistics: TunnelStatistics(received: 412_000_000,
                                                                sent: 38_400_000,
                                                                lastHandshake: Date().addingTimeInterval(-42)),
                                   isSimulated: true,
                                   profileCount: 2))
    }
}

/// Reads the snapshot for a timeline provider
enum WidgetSnapshotReader {
    static func entry(store: FleetSnapshotStore = FleetSnapshotStore()) -> TunnelEntry {
        TunnelEntry(date: Date(), snapshot: store.read())
    }

    static var placeholder: TunnelEntry {
        TunnelEntry(date: Date(), snapshot: .placeholder, isPlaceholder: true)
    }
}
