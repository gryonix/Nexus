package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.agentcontrol.VPNDNSDefaults
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.servercontrol.AgentServiceMapping
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.VPN_FAMILY
import com.skaymer.gryonixnexus.servercontrol.agentHost
import com.skaymer.gryonixnexus.servercontrol.vpnRunsOnRelay
import gryonixnexusd.v1.HostRole

/** Which machine and role a VPN agent call uses */
object VPNRelayRouting {
    /** The relay's role, when this service runs on the relay */
    fun surfaceRole(deployment: Deployment, service: ServiceID?): HostRole? =
        if (deployment.agentHost(service) == null) null else HostRole.HOST_ROLE_VPS_RELAY

    /** The machine an agent service's logs come from */
    fun logsHost(deployment: Deployment, agentServiceID: String): SSHHostID? =
        if (agentServiceID == AgentServiceMapping.agentID(ServiceID.VPN_PANEL)) {
            deployment.agentHost(ServiceID.VPN_PANEL)
        } else {
            null
        }

    /** VPN items apart, when the VPN is on the relay */
    fun <T> splitForRelay(items: List<T>, vpnOnRelay: Boolean, id: (T) -> ServiceID): Pair<List<T>, List<T>> {
        if (!vpnOnRelay) return emptyList<T>() to items
        return items.partition { id(it) in ServiceID.VPN_FAMILY }
    }

    /** On the relay, the resolvers installed at home answer */
    fun withHomeResolvers(deployment: Deployment, defaults: VPNDNSDefaults): VPNDNSDefaults {
        if (!deployment.vpnRunsOnRelay || defaults.localAddress.isEmpty()) return defaults
        val home = listOf(ServiceID.ADGUARD_HOME, ServiceID.PIHOLE).filter { it in deployment.services }
        return defaults.copy(localServices = defaults.localServices.ifEmpty { home })
    }
}
