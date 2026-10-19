package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.agentclient.AgentHostSurface
import com.skaymer.gryonixnexus.catalog.ForwardedPorts
import com.skaymer.gryonixnexus.core.WireGuardDefaults
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.servicesBehindRelay
import gryonixnexusd.v1.HostRole

/** The host surface, with a pair's tunnel and forwards */
object RelayHostSurface {
    fun of(deployment: Deployment, role: HostRole, dashboardPublicKey: String): AgentHostSurface {
        if (!deployment.hasRelayIngress) return AgentHostSurface(role = role, dashboardPublicKey = dashboardPublicKey)
        val services = deployment.servicesBehindRelay
        val context = deployment.serviceContext
        return AgentHostSurface(
            role = role,
            ptrIP = deployment.entry.host,
            tunnelEndpoint = "${deployment.entry.host}:${WireGuardDefaults.LISTEN_PORT}",
            relayWGPort = WireGuardDefaults.LISTEN_PORT,
            relayForwardedPorts = ForwardedPorts.tcp(services, context),
            relayForwardedUDPPorts = ForwardedPorts.udp(services, context),
            homeWGAddress = deployment.homeWGAddress.orEmpty(),
            dashboardPublicKey = dashboardPublicKey,
        )
    }
}
