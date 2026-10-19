package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint

object ConnectionEdit {
    data class Draft(
        val host: String,
        val port: String,
        val user: String,
    ) {
        val portNumber: Int? get() = port.trim().toIntOrNull()

        val isComplete: Boolean
            get() = host.isNotBlank() && user.isNotBlank() &&
                portNumber?.let { it in 1..65535 } == true
    }

    fun draft(node: DeploymentNode): Draft = Draft(
        host = node.endpoint.host,
        port = node.endpoint.port.toString(),
        user = node.endpoint.user,
    )

    /** The deployment with ONE machine's endpoint replaced */
    fun applying(draft: Draft, to: DeploymentNode, of: Deployment): Deployment? {
        if (!draft.isComplete) return null
        if (of.nodes.none { it.id == to.id }) return null
        val endpoint = HostEndpoint(
            host = draft.host.trim(),
            port = draft.portNumber ?: return null,
            user = draft.user.trim(),
        )
        val stored = of.storedNodes
        if (stored != null && stored.isNotEmpty()) {
            return of.copy(
                storedNodes = stored.map {
                    if (it.id == to.id) it.copy(endpoint = endpoint) else it
                },
            )
        }
        if (to.legacySlot != DeploymentNode.LegacySlot.VPS) return null
        return of.copy(entry = endpoint)
    }

    /** Which machines this screen may edit */
    fun editable(deployment: Deployment): List<DeploymentNode> {
        val stored = deployment.storedNodes
        if (stored != null && stored.isNotEmpty()) return stored
        return deployment.nodes.filter { it.legacySlot == DeploymentNode.LegacySlot.VPS }
    }
}
