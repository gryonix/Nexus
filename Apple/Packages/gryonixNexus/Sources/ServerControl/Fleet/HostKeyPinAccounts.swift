import Foundation

/// The Keychain account names a deployment's host-key pins live under
public enum HostKeyPinAccounts {
    /// Stands in for a pin the keychain failed to read
    public static let unreadable = "gryonixnexus-unreadable-pin"

    /// Where a node's pin is written today
    public static func current(deployment: UUID, node: UUID) -> String {
        "hostkey-\(deployment.uuidString)-\(node.uuidString)"
    }

    public static func current(deployment: UUID, slot: DeploymentNode.LegacySlot) -> String {
        current(deployment: deployment, node: Deployment.nodeID(for: deployment, slot: slot))
    }

    public static func legacy(deployment: UUID, slot: DeploymentNode.LegacySlot) -> String {
        "hostkey-\(deployment.uuidString)-\(slot.rawValue)"
    }
}
