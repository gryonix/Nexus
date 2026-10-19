import Foundation
import ServerControl

/// Which saved server and machine each relay id belongs to
enum RelayServers {
    private static let key = "push.relayServers"

    static func remember(_ serverID: String, as deploymentID: UUID, host: SSHHostID,
                         in defaults: UserDefaults = .standard) {
        guard !serverID.isEmpty else { return }
        let value = "\(deploymentID.uuidString)|\(hostKey(host))"
        var known = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        guard known[serverID] != value else { return }
        known[serverID] = value
        defaults.set(known, forKey: key)
    }

    static func deploymentID(of serverID: String, in defaults: UserDefaults = .standard) -> UUID? {
        target(of: serverID, in: defaults)?.deploymentID
    }

    static func target(of serverID: String, in defaults: UserDefaults = .standard)
        -> (deploymentID: UUID, host: SSHHostID?)? {
        guard let value = (defaults.dictionary(forKey: key) as? [String: String])?[serverID] else { return nil }
        let parts = value.split(separator: "|", maxSplits: 1).map(String.init)
        guard let id = parts.first.flatMap(UUID.init(uuidString:)) else { return nil }
        return (id, parts.count > 1 ? host(parsing: parts[1]) : nil)
    }

    static func hostKey(_ host: SSHHostID) -> String {
        switch host.kind {
        case .slot(let slot): return slot.rawValue
        case .node(let id): return "node:\(id.uuidString)"
        }
    }

    static func host(parsing key: String) -> SSHHostID? {
        if let slot = DeploymentNode.LegacySlot(rawValue: key) { return SSHHostID(kind: .slot(slot)) }
        return key.hasPrefix("node:") ? UUID(uuidString: String(key.dropFirst(5))).map(SSHHostID.node) : nil
    }
}
