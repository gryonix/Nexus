package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ServiceID

/** Adding and removing machines, and moving a service between them */
class NodeEditException(val reason: Reason) : Exception(reason.name) {
    enum class Reason {
        /** The address is empty, so nothing could be dialled */
        NO_ADDRESS,

        UNKNOWN_PARENT,

        PARENT_LOOP,

        /** Removing this machine would leave others reachable only through it */
        STILL_A_PARENT,

        LAST_WORKER,
    }
}

/** Adds a machine */
fun Deployment.addingNode(node: DeploymentNode): Deployment {
    if (node.endpoint.host.trim().isEmpty()) {
        throw NodeEditException(NodeEditException.Reason.NO_ADDRESS)
    }
    val updated = nodes.toMutableList()
    node.routedThrough?.let { parent ->
        if (updated.none { it.id == parent }) {
            throw NodeEditException(NodeEditException.Reason.UNKNOWN_PARENT)
        }
    }
    updated.removeAll { it.id == node.id }
    updated += node
    if (!parentChainsTerminate(updated)) {
        throw NodeEditException(NodeEditException.Reason.PARENT_LOOP)
    }
    return copy(storedNodes = updated)
}

fun Deployment.removingNode(id: String): Deployment {
    val current = nodes
    if (current.none { it.id == id }) return this
    if (current.any { it.routedThrough == id }) {
        throw NodeEditException(NodeEditException.Reason.STILL_A_PARENT)
    }
    val survivors = current.filter { it.id != id }
    if (survivors.none { it.runsServices }) {
        throw NodeEditException(NodeEditException.Reason.LAST_WORKER)
    }

    val remaining = placement?.byService?.filterValues { it != id } ?: emptyMap()
    return copy(
        storedNodes = survivors,
        placement = if (remaining.isEmpty()) null else ServicePlacement(remaining),
    )
}

/** Puts one service on one machine */
fun Deployment.placing(service: ServiceID, node: String?): Deployment {
    val current = placement?.byService.orEmpty().toMutableMap()
    if (node == null) current.remove(service.rawValue) else current[service.rawValue] = node
    return copy(placement = if (current.isEmpty()) null else ServicePlacement(current))
}

/** True when no machine's parent chain loops */
private fun parentChainsTerminate(nodes: List<DeploymentNode>): Boolean {
    val byID = nodes.associateBy { it.id }
    for (node in nodes) {
        val seen = mutableSetOf(node.id)
        var current = node.routedThrough
        while (current != null) {
            if (!seen.add(current)) return false
            current = byID[current]?.routedThrough
        }
    }
    return true
}
