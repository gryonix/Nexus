package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceSettings
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.catalog.VPNClientAccess
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import kotlin.test.assertEquals
import org.junit.jupiter.api.Test

/** Which servers the VPN section can manage devices on */
class VPNAccessTests {
    private fun server(
        id: String,
        services: Set<ServiceID> = setOf(ServiceID.WIREGUARD_VPN),
        usesAgent: Boolean = true,
        access: VPNClientAccess = VPNClientAccess.BOTH,
    ) = Deployment(
        id = id,
        name = id,
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
        services = services,
        serviceSettings = ServiceSettings(vpnClientAccess = access),
        usesAgent = usesAgent,
    )

    @Test
    fun `a server with a vpn, an agent and the owner's permission is manageable`() {
        val fleet = listOf(server("ok"))
        assertEquals(listOf("ok"), VPNAccess.manageable(fleet).map { it.id })
        assertEquals(emptyList(), VPNAccess.panelOnly(fleet).map { it.id })
    }

    @Test
    fun `an agentless server with a vpn is panel-only, not absent`() {
        // Shown and greyed rather than dropped: the devices ARE there and the
        // panel still manages them, and omitting the server would read as
        // "this server has no VPN".
        val fleet = listOf(server("no-agent", usesAgent = false))
        assertEquals(emptyList(), VPNAccess.manageable(fleet).map { it.id })
        assertEquals(listOf("no-agent"), VPNAccess.panelOnly(fleet).map { it.id })
        assertEquals(VPNAccess.PanelReason.NO_AGENT, VPNAccess.panelReason(fleet))
    }

    @Test
    fun `the owner's panel-only choice is obeyed even where the agent could`() {
        val fleet = listOf(server("by-choice", access = VPNClientAccess.PANEL))
        assertEquals(emptyList(), VPNAccess.manageable(fleet).map { it.id })
        assertEquals(VPNAccess.PanelReason.BY_CHOICE, VPNAccess.panelReason(fleet))
    }

    @Test
    fun `one of each is explained as both, not as either`() {
        val fleet = listOf(
            server("no-agent", usesAgent = false),
            server("by-choice", access = VPNClientAccess.PANEL),
        )
        assertEquals(
            VPNAccess.PanelReason.MIXED,
            VPNAccess.panelReason(VPNAccess.panelOnly(fleet)),
        )
    }

    @Test
    fun `a server without a vpn protocol is in neither list`() {
        val fleet = listOf(server("web", services = setOf(ServiceID.FORGEJO)))
        assertEquals(emptyList(), VPNAccess.manageable(fleet).map { it.id })
        assertEquals(emptyList(), VPNAccess.panelOnly(fleet).map { it.id })
        assertEquals(emptyList(), VPNAccess.withVPN(fleet).map { it.id })
    }

    @Test
    fun `the chosen protocol is honoured only while the server still runs it`() {
        val both = server("s", services = setOf(ServiceID.WIREGUARD_VPN, ServiceID.SHADOWSOCKS))
        assertEquals(ServiceID.SHADOWSOCKS, VPNAccess.protocol(ServiceID.SHADOWSOCKS, both))
        val onlyWireGuard = server("s", services = setOf(ServiceID.WIREGUARD_VPN))
        assertEquals(ServiceID.WIREGUARD_VPN, VPNAccess.protocol(ServiceID.SHADOWSOCKS, onlyWireGuard))
    }

    @Test
    fun `the protocol order is the catalog's, not the deployment's set order`() {
        val a = server("a", services = setOf(ServiceID.OPEN_VPN, ServiceID.AMNEZIA_WG))
        val b = server("b", services = setOf(ServiceID.AMNEZIA_WG, ServiceID.OPEN_VPN))
        assertEquals(VPNAccess.protocol(null, a), VPNAccess.protocol(null, b))
        assertEquals(ServiceID.AMNEZIA_WG, VPNAccess.protocol(null, a))
    }
}
