package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ServiceID

/** Where the ingress node sends a request for one service */
sealed class ServiceUpstream {
    data object Local : ServiceUpstream()

    /** The service runs on another node, reached across the mesh */
    data class Mesh(val nodeID: String, val serverName: String) : ServiceUpstream()
}

/** Why a placement cannot be served */
sealed class PlacementProblem {
    data class NeedsMeshToReachWorker(val service: ServiceID) : PlacementProblem()
}

val Deployment.hasMesh: Boolean
    get() = services.contains(ServiceID.HEADSCALE) || services.contains(ServiceID.TAILSCALE_NODE)

/** How the ingress reaches [service] */
fun Deployment.upstream(service: ServiceID, siteName: String): ServiceUpstream? {
    val worker = nodeRunning(service) ?: return null
    if (worker.terminatesPublicTraffic) return ServiceUpstream.Local
    if (worker.servesOwnTraffic) return ServiceUpstream.Local
    return ServiceUpstream.Mesh(worker.id, siteName)
}

/** Placements this deployment cannot serve, with the reason */
fun Deployment.placementProblems(): List<PlacementProblem> {
    if (hasMesh) return emptyList()
    val workers = nodes.filter { it.runsServices }
    if (workers.size <= 1) return emptyList()

    return services.mapNotNull { service ->
        val worker = nodeRunning(service) ?: return@mapNotNull null
        if (worker.terminatesPublicTraffic || worker.servesOwnTraffic) return@mapNotNull null
        PlacementProblem.NeedsMeshToReachWorker(service)
    }
}
