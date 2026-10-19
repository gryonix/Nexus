package com.skaymer.gryonixnexus.transport

import com.skaymer.gryonixnexus.servercontrol.AppSSHIdentity
import com.skaymer.gryonixnexus.servercontrol.DashboardConfig
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.SSHHostID

/** Connection parameters for the sshj-backed runner */
data class SSHConnectionSettings(
    val vpsHost: String,
    val vpsPort: Int = 22,
    val username: String,
    val homeHost: String,
    val homePort: Int = 22,
    val homeLANHost: String? = null,
    val privateKeySeed: ByteArray,
    val passwords: Map<SSHHostID, String> = emptyMap(),
    val pinnedVPSHostKey: String? = null,
    val pinnedHomeHostKey: String? = null,
    /** Machines beyond the two the fields above describe */
    val additionalNodes: List<NodeAddress> = emptyList(),
) {
    /** Where one node lives and what reaches it */
    data class NodeAddress(
        val id: String,
        val host: String,
        val port: Int = 22,
        /** The machine this one is reached THROUGH */
        val parent: SSHHostID? = null,
        val lanHost: String? = null,
        val pinnedHostKey: String? = null,
        val user: String? = null,
    )

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is SSHConnectionSettings) return false
        return vpsHost == other.vpsHost && vpsPort == other.vpsPort &&
            username == other.username && homeHost == other.homeHost &&
            homePort == other.homePort && homeLANHost == other.homeLANHost &&
            privateKeySeed.contentEquals(other.privateKeySeed) &&
            passwords == other.passwords &&
            pinnedVPSHostKey == other.pinnedVPSHostKey &&
            pinnedHomeHostKey == other.pinnedHomeHostKey &&
            additionalNodes == other.additionalNodes
    }

    override fun hashCode(): Int {
        var result = vpsHost.hashCode()
        result = 31 * result + username.hashCode()
        result = 31 * result + homeHost.hashCode()
        result = 31 * result + privateKeySeed.contentHashCode()
        result = 31 * result + additionalNodes.hashCode()
        return result
    }

    fun route(host: SSHHostID): Route? = when (val kind = host.kind) {
        is SSHHostID.Kind.Slot -> when (kind.slot) {
            DeploymentNode.LegacySlot.VPS -> Route(
                parent = null,
                address = Route.Address(vpsHost, vpsPort, pinnedVPSHostKey),
                fallback = null,
            )

            DeploymentNode.LegacySlot.HOME -> Route(
                parent = SSHHostID.VPS,
                address = Route.Address(homeHost, homePort, pinnedHomeHostKey),
                fallback = homeLANHost?.takeIf { it.isNotEmpty() }
                    ?.let { Route.Address(it, homePort, pinnedHomeHostKey) },
            )
        }

        is SSHHostID.Kind.Node -> additionalNodes.firstOrNull { it.id == kind.id }?.let { node ->
            Route(
                parent = node.parent,
                address = Route.Address(node.host, node.port, node.pinnedHostKey),
                fallback = node.lanHost?.takeIf { it.isNotEmpty() }
                    ?.let { Route.Address(it, node.port, node.pinnedHostKey) },
            )
        }
    }

    /** Whose account a command for [host] signs in as */
    fun username(host: SSHHostID): String = when (val kind = host.kind) {
        is SSHHostID.Kind.Slot -> username
        is SSHHostID.Kind.Node ->
            additionalNodes.firstOrNull { it.id == kind.id }?.user ?: username
    }

    /** One row of the route table */
    data class Route(
        val parent: SSHHostID?,
        val address: Address,
        /** Reachable without going through the parent at all */
        val fallback: Address?,
    ) {
        data class Address(
            val host: String,
            val port: Int,
            val pin: String?,
        )
    }

    companion object {
        fun additionalNodes(
            deployment: Deployment,
            pin: (SSHHostID) -> String?,
        ): List<NodeAddress> =
            deployment.nodes.filter { it.legacySlot == null }.map { node ->
                NodeAddress(
                    id = node.id,
                    host = node.endpoint.host,
                    port = node.endpoint.port,
                    parent = node.routedThrough?.let { parent ->
                        deployment.nodes.firstOrNull { it.id == parent }?.sshHost
                    },
                    pinnedHostKey = pin(node.sshHost),
                    user = node.endpoint.user.takeIf { it.isNotEmpty() },
                )
            }

        fun make(
            config: DashboardConfig,
            identity: AppSSHIdentity,
            passwords: Map<SSHHostID, String> = emptyMap(),
            pinnedVPSHostKey: String? = null,
            pinnedHomeHostKey: String? = null,
            homeLANHost: String? = null,
        ) = SSHConnectionSettings(
            vpsHost = config.vpsHost,
            vpsPort = config.sshPort,
            username = config.sshUser,
            homeHost = config.homeWGAddress,
            homePort = config.sshPort,
            homeLANHost = homeLANHost,
            privateKeySeed = identity.privateKeySeed,
            passwords = passwords,
            pinnedVPSHostKey = pinnedVPSHostKey,
            pinnedHomeHostKey = pinnedHomeHostKey,
        )
    }
}
