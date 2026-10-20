import Foundation

public enum InstalledDeploymentRecord {
    /// The record to store after a successful generation
    public static func merged(generated: Deployment, onto existing: Deployment?) -> Deployment {
        guard let existing else { return generated }
        var record = generated
        // The app's own memory of the machine.
        record.usesAgent = existing.usesAgent
        record.tags = existing.tags
        record.metricsIndicatorStyle = existing.metricsIndicatorStyle
        record.iconSymbol = existing.iconSymbol
        record.tintName = existing.tintName
        record.cardSize = existing.cardSize
        record.timeouts = existing.timeouts
        record.wgInterface = existing.wgInterface
        record.storedNodes = existing.storedNodes
        record.placement = existing.placement
        record.vpnOnRelay = existing.vpnOnRelay
        record.wakeOnLANMAC = existing.wakeOnLANMAC
        record.wakeOnLANBroadcast = existing.wakeOnLANBroadcast
        return record
    }
}
