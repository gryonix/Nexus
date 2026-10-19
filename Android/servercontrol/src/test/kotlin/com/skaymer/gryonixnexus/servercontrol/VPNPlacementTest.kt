package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.catalog.services.VPNPanelService
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class VPNPlacementTest {
    private fun pair(vpnOnRelay: Boolean? = null) = Deployment(
        id = "22222222-2222-2222-2222-222222222222",
        name = "B",
        topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        domain = "example.net",
        entry = HostEndpoint(host = "203.0.113.10", port = 2222, user = "admin"),
        homeWGAddress = "10.8.0.2",
        services = setOf(ServiceID.WIREGUARD_VPN, ServiceID.XRAY_REALITY, ServiceID.VPN_PANEL, ServiceID.NEXTCLOUD),
        usesAgent = true,
        vpnOnRelay = vpnOnRelay,
    )

    @Test
    fun `at home the VPN runs with everything else`() {
        val deployment = pair()
        assertFalse(deployment.vpnRunsOnRelay)
        assertEquals(deployment.servicesHost, deployment.vpnHost)
        assertEquals(deployment.relayNode?.sshHost, deployment.otherVPNHost)
        assertEquals(deployment.servicesHost, deployment.hostRunning(ServiceID.WIREGUARD_VPN))
        assertEquals(deployment.services, deployment.servicesBehindRelay.map { it.id }.toSet())
        assertNull(deployment.agentHost(ServiceID.WIREGUARD_VPN))
    }

    @Test
    fun `on the relay only the VPN family moves`() {
        val deployment = pair(vpnOnRelay = true)
        val relay = deployment.relayNode?.sshHost
        assertTrue(deployment.vpnRunsOnRelay)
        assertEquals(relay, deployment.vpnHost)
        assertEquals(deployment.servicesHost, deployment.otherVPNHost)
        for (service in listOf(ServiceID.WIREGUARD_VPN, ServiceID.XRAY_REALITY, ServiceID.VPN_PANEL)) {
            assertEquals(relay, deployment.hostRunning(service), service.rawValue)
            assertEquals(relay, deployment.agentHost(service), service.rawValue)
        }
        assertEquals(deployment.servicesHost, deployment.hostRunning(ServiceID.NEXTCLOUD))
        assertNull(deployment.agentHost(ServiceID.NEXTCLOUD))
        assertEquals(listOf(ServiceID.NEXTCLOUD), deployment.servicesBehindRelay.map { it.id })
    }

    @Test
    fun `one machine never runs the VPN on a relay`() {
        val deployment = Deployment(
            id = "11111111-1111-1111-1111-111111111111",
            name = "A",
            topology = Topology.SINGLE_HOST,
            domain = "example.net",
            entry = HostEndpoint(host = "203.0.113.10", user = "root"),
            services = setOf(ServiceID.WIREGUARD_VPN),
            usesAgent = true,
            vpnOnRelay = true,
        )
        assertNull(deployment.relayNode)
        assertFalse(deployment.canRunVPNOnRelay)
        assertFalse(deployment.vpnRunsOnRelay)
        assertEquals(deployment.servicesHost, deployment.vpnHost)
        assertNull(deployment.otherVPNHost)
    }

    @Test
    fun `the state directories follow the installed protocols`() {
        val base = pair()
        val deployment = base.copy(serviceSettings = base.serviceSettings.copy(xrayRealityPath = "/opt/xray"))
        assertEquals(listOf(VPNPanelService.PATH, "/opt/xray"), deployment.vpnStateDirectories)
    }

    @Test
    fun `the flag survives saving and old files read as home`() {
        val moved = pair().movingVPN(toRelay = true)
        val decoded = DeploymentListCodec.decode(DeploymentListCodec.encode(listOf(moved))).single()
        assertTrue(decoded.vpnRunsOnRelay)
        assertNull(moved.movingVPN(toRelay = false).vpnOnRelay)
        val old = DeploymentListCodec.decode(DeploymentListCodec.encode(listOf(pair()))).single()
        assertNull(old.vpnOnRelay)
        assertFalse(DeploymentListCodec.encode(listOf(pair())).contains("vpnOnRelay"))
    }
}
