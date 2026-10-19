package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.agentcontrol.VPNDNSDefaults
import com.skaymer.gryonixnexus.agentcontrol.VPNDNSPriority
import com.skaymer.gryonixnexus.app.servers.AddServiceViewModel
import com.skaymer.gryonixnexus.app.servers.RelayHostSurface
import com.skaymer.gryonixnexus.app.servers.ServiceInstallPlan
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import gryonixnexusd.v1.HostRole
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The VPN on the relay before a home server */
class VPNRelayTests {
    private fun pair(vpnOnRelay: Boolean? = null) = Deployment(
        id = "22222222-2222-2222-2222-222222222222",
        name = "B",
        topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        domain = "example.net",
        entry = HostEndpoint(host = "203.0.113.10", port = 2222, user = "admin"),
        homeWGAddress = "10.8.0.2",
        services = setOf(ServiceID.WIREGUARD_VPN, ServiceID.SHADOWSOCKS, ServiceID.VPN_PANEL, ServiceID.NEXTCLOUD),
        usesAgent = true,
        vpnOnRelay = vpnOnRelay,
    )

    private fun forwardedUDP(deployment: Deployment): Set<Int> =
        RelayHostSurface.of(deployment, HostRole.HOST_ROLE_VPS_RELAY, "").relayForwardedUDPPorts.toSet()

    @Test
    fun `the relay stops sending VPN ports home once the VPN moves`() {
        val wireGuard = pair().serviceSettings.wireguardVPNPort
        assertTrue(wireGuard in forwardedUDP(pair()))
        assertFalse(wireGuard in forwardedUDP(pair(vpnOnRelay = true)))
        assertNotEquals(AddServiceViewModel.forwardedPorts(pair()), AddServiceViewModel.forwardedPorts(pair(vpnOnRelay = true)))
    }

    @Test
    fun `a plan splits only when the VPN is on the relay`() {
        val services = listOf(ServiceID.WIREGUARD_VPN, ServiceID.NEXTCLOUD).mapNotNull(ServiceRegistry::service)
        val steps = ServiceInstallPlan.steps(services, emptySet())
        val home = VPNRelayRouting.splitForRelay(steps, vpnOnRelay = false) { it.service.id }
        assertTrue(home.first.isEmpty())
        assertEquals(steps.size, home.second.size)
        val relay = VPNRelayRouting.splitForRelay(steps, vpnOnRelay = true) { it.service.id }
        assertEquals(listOf(ServiceID.WIREGUARD_VPN), relay.first.map { it.service.id })
        assertEquals(listOf(ServiceID.NEXTCLOUD), relay.second.map { it.service.id })
    }

    @Test
    fun `relay installs carry the relay role`() {
        assertEquals(HostRole.HOST_ROLE_VPS_RELAY, VPNRelayRouting.surfaceRole(pair(vpnOnRelay = true), ServiceID.SHADOWSOCKS))
        assertNull(VPNRelayRouting.surfaceRole(pair(vpnOnRelay = true), ServiceID.NEXTCLOUD))
        assertNull(VPNRelayRouting.surfaceRole(pair(), ServiceID.SHADOWSOCKS))
    }

    @Test
    fun `VPN logs come from the machine the VPN runs on`() {
        assertEquals(SSHHostID.VPS, VPNRelayRouting.logsHost(pair(vpnOnRelay = true), "vpn"))
        assertNull(VPNRelayRouting.logsHost(pair(vpnOnRelay = true), "nextcloud"))
        assertNull(VPNRelayRouting.logsHost(pair(), "vpn"))
    }

    @Test
    fun `the home resolver is offered while the VPN is on the relay`() {
        val deployment = pair(vpnOnRelay = true).let { it.copy(services = it.services + ServiceID.ADGUARD_HOME) }
        val answered = VPNRelayRouting.withHomeResolvers(deployment, VPNDNSDefaults(localAddress = "10.53.0.53"))
        assertEquals(listOf(ServiceID.ADGUARD_HOME), answered.localServices)
        val atHome = VPNRelayRouting.withHomeResolvers(pair(), VPNDNSDefaults(localAddress = "10.53.0.53"))
        assertTrue(atHome.localServices.isEmpty())
    }

    @Test
    fun `the DNS order is edited within its bounds`() {
        val edit = VPNDNSPriorityEditing
        val order = listOf("local", "1.1.1.1", "9.9.9.9")
        assertEquals(listOf("1.1.1.1", "local", "9.9.9.9"), edit.moveUp(1, order))
        assertEquals(order, edit.moveUp(0, order))
        assertEquals(order, edit.moveDown(2, order))
        assertEquals(listOf("1.1.1.1", "9.9.9.9"), edit.remove(0, order))
        assertEquals(listOf("local"), edit.remove(0, listOf("local")), "the last resolver stays")
        assertEquals(order + "8.8.8.8", edit.add("8.8.8.8", order))
        assertEquals(order, edit.add("1.1.1.1", order), "no repeats")
        val full = order + "8.8.8.8"
        assertEquals(full, edit.add("1.0.0.1", full), "four at most")
        assertFalse(edit.canAdd(full))
    }

    @Test
    fun `entries are named for people`() {
        assertEquals(VPNDNSPriorityEditing.Entry.Local, VPNDNSPriorityEditing.describe(VPNDNSPriority.LOCAL))
        val cloudflare = assertIs<VPNDNSPriorityEditing.Entry.Preset>(VPNDNSPriorityEditing.describe("1.1.1.1"))
        assertEquals("Cloudflare", cloudflare.preset.provider)
        assertEquals(
            VPNDNSPriorityEditing.Entry.Address("203.0.113.53"),
            VPNDNSPriorityEditing.describe("203.0.113.53"),
        )
    }

    @Test
    fun `the public choices are one per provider, by first address`() {
        val choices = VPNDNSPriorityEditing.publicChoices
        assertEquals(choices.map { it.provider }.distinct(), choices.map { it.provider })
        assertTrue(choices.all { it.variant == null })
        assertEquals("1.1.1.1", choices.first().addresses.first())
        assertEquals("203.0.113.53", VPNDNSPriorityEditing.typed(" 203.0.113.53 "))
        assertNull(VPNDNSPriorityEditing.typed("1.1.1.1, 9.9.9.9"))
    }
}
