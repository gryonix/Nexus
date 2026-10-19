package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.agentcontrol.VPNClientDevice
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** What the configuration picker offers and marks */
class TunnelChoicesTests {
    private val wireguard = ServiceID.WIREGUARD_VPN

    private fun profile(serverId: String = "S-1", clientId: String = "", name: String = "") =
        LastTunnel.Profile("phone.conf", "[Interface]", wireguard, "middle", serverId, clientId, name)

    @Test
    fun `an own configuration is the one in use when no other device was picked`() {
        assertTrue(TunnelChoices.isOwnInUse(profile(), "S-1", wireguard, ownId = "id-own"))
    }

    @Test
    fun `a configuration picked by the own device's id still counts as the own one`() {
        val picked = profile(clientId = "id-own")
        assertTrue(TunnelChoices.isOwnInUse(picked, "S-1", wireguard, ownId = "id-own"))
        assertFalse(TunnelChoices.isInUse(picked, "S-1", wireguard, "id-other"))
    }

    @Test
    fun `another device's configuration marks only that device`() {
        val picked = profile(clientId = "id-laptop", name = "laptop")
        assertTrue(TunnelChoices.isInUse(picked, "S-1", wireguard, "id-laptop"))
        assertFalse(TunnelChoices.isOwnInUse(picked, "S-1", wireguard, ownId = "id-own"))
    }

    @Test
    fun `nothing is marked on another server or protocol`() {
        val picked = profile(clientId = "id-laptop")
        assertFalse(TunnelChoices.isInUse(picked, "S-2", wireguard, "id-laptop"))
        assertFalse(TunnelChoices.isInUse(picked, "S-1", ServiceID.AMNEZIA_WG, "id-laptop"))
        assertFalse(TunnelChoices.isOwnInUse(profile(), "S-2", wireguard, null))
    }

    @Test
    fun `a saved tunnel from before the picker marks nothing`() {
        val legacy = profile(serverId = "")
        assertFalse(TunnelChoices.isOwnInUse(legacy, "", wireguard, null))
        assertFalse(TunnelChoices.isOwnInUse(null, "S-1", wireguard, null))
    }

    @Test
    fun `the other devices leave the own one out`() {
        val devices = listOf(
            VPNClientDevice("id-own", "phone", "10.9.0.2/32"),
            VPNClientDevice("id-laptop", "laptop", "10.9.0.3/32"),
        )
        assertEquals(listOf("laptop"), TunnelChoices.others(devices, "id-own").map { it.name })
        assertEquals(2, TunnelChoices.others(devices, null).size)
    }

    @Test
    fun `the configuration name falls back to the file`() {
        assertEquals("laptop", TunnelChoices.configurationName(profile(name = "laptop")))
        assertEquals("phone.conf", TunnelChoices.configurationName(profile()))
    }

    @Test
    fun `only the protocols this phone can carry are offered`() {
        val server = Deployment(
            id = "S-1", name = "middle", topology = Topology.SINGLE_HOST, domain = "example.test",
            entry = HostEndpoint(host = "203.0.113.40", user = "root"),
            services = setOf(wireguard, ServiceID.OPEN_VPN), usesAgent = true,
        )
        val offered = TunnelChoices.protocols(server) { it == wireguard }
        assertEquals(listOf(wireguard), offered)
    }

    @Test
    fun `a switched server keeps the protocol it has, else takes its first`() {
        val amnezia = ServiceID.AMNEZIA_WG
        assertEquals(amnezia, TunnelChoices.landingProtocol(listOf(wireguard, amnezia), amnezia))
        assertEquals(ServiceID.SHADOWSOCKS, TunnelChoices.landingProtocol(listOf(ServiceID.SHADOWSOCKS), wireguard))
        assertNull(TunnelChoices.landingProtocol(emptyList(), wireguard))
    }

    @Test
    fun `the device in use is the picked one, else this phone's own`() {
        assertEquals("id-laptop", TunnelChoices.clientId(profile(clientId = "id-laptop"), "id-own"))
        assertEquals("id-own", TunnelChoices.clientId(profile(), "id-own"))
        assertNull(TunnelChoices.clientId(profile(), null))
    }

    @Test
    fun `the DNS is the one the server lists for that device`() {
        val devices = listOf(VPNClientDevice("id-own", "phone", "10.9.0.2/32", listOf(LocalDNS.SERVER_ADDRESS)))
        assertEquals(listOf(LocalDNS.SERVER_ADDRESS), TunnelChoices.dns(devices, "id-own"))
        assertNull(TunnelChoices.dns(devices, "id-laptop"))
    }

    @Test
    fun `the endpoint is read from a WireGuard file and from a proxy link`() {
        val wireGuardText = "[Interface]\nPrivateKey = x\nAddress = 10.9.0.2/32\n" +
            "[Peer]\nPublicKey = y\nEndpoint = vpn.example.net:51820\nAllowedIPs = 0.0.0.0/0\n"
        val wg = LastTunnel.Profile("phone.conf", wireGuardText, wireguard, "middle")
        assertEquals("vpn.example.net:51820", TunnelChoices.endpoint(wg))
        val link = "ss://YWVzLTI1Ni1nY206c2VjcmV0@vpn.example.net:8388#phone\ndns=1.1.1.1"
        val proxy = LastTunnel.Profile("phone", link, ServiceID.SHADOWSOCKS, "middle")
        assertEquals("vpn.example.net:8388", TunnelChoices.endpoint(proxy))
        assertNull(TunnelChoices.endpoint(LastTunnel.Profile("x", "garbage", wireguard, "middle")))
    }

    @Test
    fun `a switch keeps the DNS the stored tunnel names`() {
        val proxy = LastTunnel.Profile("iPhone", "ss://x@h.example.net:8388\ndns=1.1.1.1,1.0.0.1", ServiceID.SHADOWSOCKS, "s")
        assertEquals(listOf("1.1.1.1", "1.0.0.1"), TunnelChoices.carriedDNS(proxy))
        val wireGuard = LastTunnel.Profile("p", "[Interface]\nAddress = 10.9.0.2/32\nDNS = 10.53.0.53\n", ServiceID.WIREGUARD_VPN, "s")
        assertEquals(listOf("10.53.0.53"), TunnelChoices.carriedDNS(wireGuard))
        assertEquals(emptyList<String>(), TunnelChoices.carriedDNS(null))
    }
}
