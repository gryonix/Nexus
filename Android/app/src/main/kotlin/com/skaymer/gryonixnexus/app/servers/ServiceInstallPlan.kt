package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceID

/** What one install run sends to the server, in order */
object ServiceInstallPlan {
    /** One install; other new VPN protocols ride along */
    data class Step(val service: ManagedService, val alsoProtocols: Set<ServiceID>)

    /** New services only; new VPN protocols as one step */
    fun steps(services: List<ManagedService>, installed: Set<ServiceID>): List<Step> {
        val fresh = services.filter { it.id !in installed }.distinctBy { it.id }
        val protocols = fresh.map { it.id }.filter { it in ServiceID.VPN_PROTOCOLS }
        return fresh.mapNotNull { service ->
            when {
                service.id !in ServiceID.VPN_PROTOCOLS -> Step(service, emptySet())
                service.id == protocols.first() -> Step(service, protocols.drop(1).toSet())
                else -> null
            }
        }
    }

    /** Repair and reinstall: every service again, tunnel kept */
    fun rerun(installed: List<ManagedService>): List<Step> =
        steps(agentRun(installed.filter { it.id != ServiceID.CLOUDFLARED }, emptySet()), emptySet())

    /** What setup sends the agent; VPN protocols once */
    fun agentRun(chosen: List<ManagedService>, onHost: Set<ServiceID>): List<ManagedService> {
        val protocols = chosen.map { it.id }.filter { it in ServiceID.VPN_PROTOCOLS }
        val vpnNeeded = protocols.any { it !in onHost }
        return chosen.filter { service ->
            when (service.id) {
                in ServiceID.VPN_PROTOCOLS -> vpnNeeded && service.id == protocols.first()
                ServiceID.VPN_PANEL -> protocols.isEmpty() && service.id !in onHost
                else -> service.id !in onHost
            }
        }
    }
}
