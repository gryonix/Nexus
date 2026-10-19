package com.skaymer.gryonixnexus.servercontrol

/** The keystore account names a deployment's host-key pins live under */
object HostKeyPinAccounts {
    /** Where a node's pin is written today */
    fun current(deployment: String, node: String): String = "hostkey-$deployment-$node"

    fun current(deployment: String, slot: DeploymentNode.LegacySlot): String =
        current(deployment, DeploymentNode.nodeID(deployment, slot))

    fun legacy(deployment: String, slot: DeploymentNode.LegacySlot): String =
        "hostkey-$deployment-${slot.name.lowercase()}"

    /** A typed-in jump host's pin, by its host:port */
    fun bastion(deployment: String, endpoint: String): String =
        "gryonixnexus.hostkey.bastion.$deployment.$endpoint"
}
