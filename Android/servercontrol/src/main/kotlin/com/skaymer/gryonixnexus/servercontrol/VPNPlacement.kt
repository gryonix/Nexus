package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.services.VPNPanelService

/** The VPN protocols and their panel; they move together */
val ServiceID.Companion.VPN_FAMILY: Set<ServiceID>
    get() = ServiceID.VPN_PROTOCOLS + ServiceID.VPN_PANEL

/** The relay that publishes this deployment, if any */
val Deployment.relayNode: DeploymentNode?
    get() = nodes.firstOrNull { it.terminatesPublicTraffic && !it.runsServices }

/** Whether the VPN runs on the relay */
val Deployment.vpnRunsOnRelay: Boolean
    get() = vpnOnRelay == true && relayNode != null

/** Whether this deployment can move its VPN to the relay */
val Deployment.canRunVPNOnRelay: Boolean
    get() = usesAgent && relayNode != null

/** The machine the VPN runs on */
val Deployment.vpnHost: SSHHostID
    get() = relayNode?.takeIf { vpnRunsOnRelay }?.sshHost ?: servicesHost

/** The other machine the VPN could run on */
val Deployment.otherVPNHost: SSHHostID?
    get() {
        val relay = relayNode ?: return null
        return if (vpnRunsOnRelay) servicesHost else relay.sshHost
    }

/** Installed VPN protocols and panel */
val Deployment.installedVPNServices: Set<ServiceID>
    get() = services.intersect(ServiceID.VPN_FAMILY)

/** Installed services whose ports the relay sends home */
val Deployment.servicesBehindRelay: List<ManagedService>
    get() {
        val installed = ServiceRegistry.services(services)
        if (!vpnRunsOnRelay) return installed
        return installed.filter { it.id !in ServiceID.VPN_FAMILY }
    }

/** The machine that runs this service, when not the default */
fun Deployment.agentHost(service: ServiceID?): SSHHostID? =
    if (service != null && vpnRunsOnRelay && service in ServiceID.VPN_FAMILY) vpnHost else null

/** The VPN's directories that hold its keys and devices */
val Deployment.vpnStateDirectories: List<String>
    get() {
        val settings = serviceSettings
        val byProtocol = listOf(
            ServiceID.AMNEZIA_WG to settings.amneziaWGPath,
            ServiceID.SHADOWSOCKS to settings.shadowsocksPath,
            ServiceID.XRAY_REALITY to settings.xrayRealityPath,
            ServiceID.OPEN_VPN to settings.openVPNPath,
        )
        return listOf(VPNPanelService.PATH) + byProtocol.filter { it.first in services }.map { it.second }
    }

/** This deployment with the VPN moved */
fun Deployment.movingVPN(toRelay: Boolean): Deployment = copy(vpnOnRelay = if (toRelay) true else null)
