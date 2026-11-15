import Foundation
import ServerControl
import VPNTunnel

/// A server's quiet summary push, turned into widget readings
enum WidgetPush {
    static let kind = "gnx.widgets"

    /// True when the snapshot took new readings
    static func received(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let gnx = userInfo["gnx"] as? [String: Any], gnx["kind"] as? String == kind,
              let serverID = gnx["server_id"] as? String,
              let deploymentID = RelayServers.deploymentID(of: serverID),
              let deployment = ((try? FileDeploymentStore().load()) ?? []).first(where: { $0.id == deploymentID })
        else { return false }
        let at = (gnx["at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? Date()
        let written = FleetSnapshotStore().updateServer(id: deployment.id, name: deployment.name) { server in
            apply(gnx, at: at, to: &server)
        }
        if written { WidgetRefresh.reload() }
        return written
    }

    /// The readings the push carries, over what the server had
    static func apply(_ gnx: [String: Any], at: Date, to server: inout FleetSnapshot.Server) {
        if let part = gnx["services"] as? [String: Any], let total = int(part["total"]), total > 0 {
            server.services = .init(total: total, needingAttention: int(part["attention"]) ?? 0, takenAt: at)
        }
        if let part = gnx["security"] as? [String: Any] {
            server.security = .init(isPresent: flag(part["present"]), engineRunning: flag(part["engine"]),
                                    bouncerRunning: flag(part["bouncer"]), alertsLast24h: int(part["alerts"]) ?? 0,
                                    localBans: int(part["bans"]) ?? 0,
                                    communityBlocklistIPs: int(part["blocklist"]) ?? 0, takenAt: at)
        }
        if let part = gnx["backups"] as? [String: Any] {
            server.backups = .init(isOn: flag(part["on"]), everyHours: int(part["every_hours"]),
                                   everyDays: int(part["every_days"]), servicesCovered: int(part["services"]) ?? 0,
                                   retention: int(part["retention"]) ?? 0, takenAt: at)
        }
        if let part = gnx["metrics"] as? [String: Any], let memTotal = int64(part["mem_total"]) {
            server.metrics = .init(cpuPercent: (part["cpu"] as? NSNumber)?.doubleValue,
                                   memUsedBytes: int64(part["mem_used"]) ?? 0, memTotalBytes: memTotal,
                                   diskUsedBytes: int64(part["disk_used"]) ?? 0,
                                   diskTotalBytes: int64(part["disk_total"]) ?? 0,
                                   machineLabel: server.name, takenAt: at)
        }
    }

    private static func int(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }
    private static func int64(_ value: Any?) -> Int64? { (value as? NSNumber)?.int64Value }
    private static func flag(_ value: Any?) -> Bool { (value as? NSNumber)?.boolValue ?? false }
}
