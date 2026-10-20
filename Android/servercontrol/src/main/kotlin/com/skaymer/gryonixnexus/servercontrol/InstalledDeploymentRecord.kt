package com.skaymer.gryonixnexus.servercontrol

/** What the configurator generated, written onto the record it replaces */
object InstalledDeploymentRecord {
    /** The record to store after a successful generation */
    fun merged(generated: Deployment, existing: Deployment?): Deployment {
        if (existing == null) return generated
        return generated.copy(
            // The app's own memory of the machine.
            usesAgent = existing.usesAgent,
            tags = existing.tags,
            metricsIndicatorStyle = existing.metricsIndicatorStyle,
            iconSymbol = existing.iconSymbol,
            tintName = existing.tintName,
            cardSize = existing.cardSize,
            timeouts = existing.timeouts,
            wgInterface = existing.wgInterface,
            storedNodes = existing.storedNodes,
            placement = existing.placement,
            vpnOnRelay = existing.vpnOnRelay,
            wakeOnLANMAC = existing.wakeOnLANMAC,
            wakeOnLANBroadcast = existing.wakeOnLANBroadcast,
        )
    }
}
