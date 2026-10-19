package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceID
import kotlinx.serialization.Serializable

enum class ServiceMoveRefusal {
    NOT_MOVABLE,
    NO_AGENT,
    SAME_MACHINE,
    UNKNOWN_MACHINE,
    TARGET_DOES_NOT_RUN_SERVICES,
    NO_FRONT,
}

data class ServiceMoveRoute(
    val service: ServiceID,
    val source: DeploymentNode,
    val target: DeploymentNode,
    /** The machine whose Caddy answers the domain */
    val front: DeploymentNode,
) {
    val sourceIsFront: Boolean get() = source.id == front.id
    val targetIsFront: Boolean get() = target.id == front.id

    val sourceEntryAddress: String? get() = if (sourceIsFront) null else source.endpoint.host

    val targetEntryAddress: String? get() = if (targetIsFront) null else target.endpoint.host
}

/** Which services can travel between machines */
object ServiceMovePolicy {
    private val tiedToTheirAddress: Set<ServiceID> = setOf(
        ServiceID.AUTHELIA, ServiceID.ADGUARD_HOME, ServiceID.PIHOLE,
        ServiceID.HEADSCALE, ServiceID.TAILSCALE_NODE, ServiceID.VPN_PANEL,
    )

    fun isMovable(service: ManagedService, context: ServiceContext): Boolean {
        val actions = service.actions(context)
        if (actions.restore == null || actions.backup?.wrapper == null) return false
        if (service.webIngress(context) == null || service.firewallPorts(context).isNotEmpty()) return false
        return service.id !in tiedToTheirAddress && service.id !in ServiceID.VPN_PROTOCOLS
    }
}

val Deployment.frontNode: DeploymentNode?
    get() = nodes.firstOrNull { it.servesOwnTraffic && it.runsServices }
        ?: nodes.firstOrNull { it.terminatesPublicTraffic && it.runsServices }

fun Deployment.moveRoute(service: ServiceID, target: String): MoveRouteResult {
    if (!usesAgent) return MoveRouteResult.Refused(ServiceMoveRefusal.NO_AGENT)
    val targetNode = nodes.firstOrNull { it.id == target }
        ?: return MoveRouteResult.Refused(ServiceMoveRefusal.UNKNOWN_MACHINE)
    if (!targetNode.runsServices) {
        return MoveRouteResult.Refused(ServiceMoveRefusal.TARGET_DOES_NOT_RUN_SERVICES)
    }
    val source = nodeRunning(service) ?: return MoveRouteResult.Refused(ServiceMoveRefusal.UNKNOWN_MACHINE)
    if (source.id == targetNode.id) return MoveRouteResult.Refused(ServiceMoveRefusal.SAME_MACHINE)
    val front = frontNode ?: return MoveRouteResult.Refused(ServiceMoveRefusal.NO_FRONT)
    return MoveRouteResult.Ready(ServiceMoveRoute(service, source, targetNode, front))
}

sealed class MoveRouteResult {
    data class Ready(val route: ServiceMoveRoute) : MoveRouteResult()
    data class Refused(val reason: ServiceMoveRefusal) : MoveRouteResult()
}

/** The stages of a move, in the order they run */
enum class ServiceMoveStep {
    CHECK, INSTALL, BACKUP, STOP, SEND, RESTORE, SWITCH_ENTRY, VERIFY, FINISH,
}

@Serializable
data class ServiceMoveRecord(
    val deployment: String,
    val service: String,
    val source: String,
    val target: String,
    val transferID: String,
    val step: ServiceMoveStep = ServiceMoveStep.CHECK,
    val installedOnTarget: Boolean = false,
    val sourceStopped: Boolean = false,
    val switchedEntry: Boolean = false,
    val archivePath: String? = null,
    val archiveName: String? = null,
    val archiveBytes: Long? = null,
    val sha256: String? = null,
    val sentBytes: Long? = null,
    val targetArchivePath: String? = null,
)
