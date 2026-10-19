package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.profile.LocalProxyAccess
import com.skaymer.gryonixnexus.profile.ProxyLinkConfig
import com.skaymer.gryonixnexus.profile.WireGuardQuickConfig
import com.skaymer.gryonixnexus.profile.XrayConfiguration
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** Dialing a configuration's domain by a pinned address */
class EndpointPinsTests {
    private val pin = EndpointPin("vpn.example.org", "203.0.113.5")

    private val wireguardText = """
        [Interface]
        PrivateKey = cHJpdmF0ZQ==
        Address = 10.9.0.4/32
        DNS = 1.1.1.1

        [Peer]
        PublicKey = cHVibGlj
        Endpoint = vpn.example.org:51820
        AllowedIPs = 0.0.0.0/0, ::/0
        PersistentKeepalive = 25
    """.trimIndent()

    private val realityLink = "vless://0b6a0c3e-7f1a-4a43-9d7e-4d4a4bfa1c2e@vpn.example.org:443" +
        "?security=reality&sni=www.example.net&fp=chrome&pbk=cHVibGlj&sid=ab12&type=tcp&flow=xtls-rprx-vision#phone"

    @Test
    fun `only the host of host and port is replaced`() {
        assertEquals("203.0.113.5:51820", EndpointPins.replaceHost("vpn.example.org:51820", "203.0.113.5"))
    }

    @Test
    fun `an IPv6 address is bracketed and keeps the port`() {
        assertEquals("[2001:db8::1]:51820", EndpointPins.replaceHost("vpn.example.org:51820", "2001:db8::1"))
        assertEquals("203.0.113.5:443", EndpointPins.replaceHost("[2001:db8::7]:443", "203.0.113.5"))
    }

    @Test
    fun `the host is read without port or brackets`() {
        assertEquals("vpn.example.org", EndpointPins.hostOf("vpn.example.org:51820"))
        assertEquals("2001:db8::7", EndpointPins.hostOf("[2001:db8::7]:443"))
    }

    @Test
    fun `public addresses pass`() {
        listOf("203.0.113.5", "198.51.100.20", "2001:db8::1", "::ffff:203.0.113.5")
            .forEach { assertTrue(EndpointPins.isPublicAddress(it), it) }
    }

    @Test
    fun `private, local and multicast IPv4 addresses are refused`() {
        listOf(
            "0.1.2.3", "10.0.0.1", "100.64.0.1", "100.127.255.254", "127.0.0.1", "169.254.1.1",
            "172.16.0.1", "172.31.255.255", "192.168.1.1", "198.18.0.1", "198.19.255.1",
            "224.0.0.1", "239.1.1.1", "255.255.255.255",
        ).forEach { assertFalse(EndpointPins.isPublicAddress(it), it) }
    }

    @Test
    fun `the edges of the refused IPv4 ranges stay public`() {
        listOf("100.63.255.255", "100.128.0.1", "172.15.0.1", "172.32.0.1", "198.17.0.1", "198.20.0.1", "223.255.255.254")
            .forEach { assertTrue(EndpointPins.isPublicAddress(it), it) }
    }

    @Test
    fun `local and multicast IPv6 addresses are refused`() {
        listOf("::1", "::", "fc00::1", "fd12:3456::1", "fe80::1", "febf::1", "ff02::1", "::ffff:10.0.0.1", "fe80::1%wlan0")
            .forEach { assertFalse(EndpointPins.isPublicAddress(it), it) }
    }

    @Test
    fun `text that is not an address is neither public nor literal`() {
        listOf("vpn.example.org", "256.1.1.1", "1.2.3", "2001:db8:::1", "12345::1", "")
            .forEach {
                assertFalse(EndpointPins.isPublicAddress(it), it)
                assertFalse(EndpointPins.isAddressLiteral(it), it)
            }
    }

    @Test
    fun `IPv4 is preferred among the answers`() {
        assertEquals("203.0.113.5", EndpointPins.preferred(listOf("2001:db8::1", "203.0.113.5")))
        assertEquals("2001:db8::1", EndpointPins.preferred(listOf("2001:db8::1")))
        assertNull(EndpointPins.preferred(emptyList()))
    }

    @Test
    fun `a lookup becomes a pin, a refusal, or nothing found`() {
        assertEquals(PinOutcome.Pinned(pin), EndpointPins.outcome("vpn.example.org", listOf("2001:db8::1", "203.0.113.5")))
        assertEquals(PinOutcome.Private("10.8.0.1"), EndpointPins.outcome("vpn.example.org", listOf("10.8.0.1")))
        assertEquals(PinOutcome.NotFound, EndpointPins.outcome("vpn.example.org", emptyList()))
    }

    @Test
    fun `the pin applies only while the configuration names its host`() {
        val wireguard = ServiceID.WIREGUARD_VPN
        assertEquals("203.0.113.5", EndpointPins.address(pin, wireguard, "vpn.example.org:51820"))
        assertEquals("203.0.113.5", EndpointPins.address(pin, wireguard, "VPN.example.org:51820"))
        assertNull(EndpointPins.address(pin, wireguard, "edge.example.org:51820"))
        assertNull(EndpointPins.address(pin, wireguard, "198.51.100.9:51820"))
        assertNull(EndpointPins.address(null, wireguard, "vpn.example.org:51820"))
        assertNull(EndpointPins.address(pin, wireguard, null))
    }

    @Test
    fun `only WireGuard, AmneziaWG, Shadowsocks and Xray take a pin`() {
        listOf(ServiceID.WIREGUARD_VPN, ServiceID.AMNEZIA_WG, ServiceID.SHADOWSOCKS, ServiceID.XRAY_REALITY)
            .forEach { assertEquals("203.0.113.5", EndpointPins.address(pin, it, "vpn.example.org:443"), it.rawValue) }
        listOf(ServiceID.OPEN_VPN, ServiceID.VPN_PANEL, ServiceID.HEADSCALE)
            .forEach { assertNull(EndpointPins.address(pin, it, "vpn.example.org:443"), it.rawValue) }
    }

    @Test
    fun `an address endpoint offers no choice`() {
        assertFalse(EndpointPins.offersChoice(ServiceID.WIREGUARD_VPN, "203.0.113.5:51820"))
        assertFalse(EndpointPins.offersChoice(ServiceID.WIREGUARD_VPN, "[2001:db8::1]:51820"))
        assertTrue(EndpointPins.offersChoice(ServiceID.WIREGUARD_VPN, "vpn.example.org:51820"))
        assertFalse(EndpointPins.offersChoice(ServiceID.OPEN_VPN, "vpn.example.org:1194"))
    }

    @Test
    fun `the shown endpoint follows the pin`() {
        assertEquals("203.0.113.5:51820", EndpointPins.pinnedEndpoint(pin, ServiceID.AMNEZIA_WG, "vpn.example.org:51820"))
        assertNull(EndpointPins.pinnedEndpoint(pin, ServiceID.AMNEZIA_WG, "edge.example.org:51820"))
    }

    @Test
    fun `the key names server, protocol and device`() {
        val own = LastTunnel.Profile("phone.conf", "", ServiceID.WIREGUARD_VPN, "orion", "S-1", "", "Pixel")
        val other = own.copy(clientId = "id-laptop", clientName = "laptop")
        val bare = own.copy(serverId = "", clientName = "")
        assertEquals("S-1/wireguard-vpn/Pixel", EndpointPins.key(own))
        assertEquals("S-1/wireguard-vpn/id-laptop", EndpointPins.key(other))
        assertEquals("/wireguard-vpn/phone.conf", EndpointPins.key(bare))
    }

    @Test
    fun `the WireGuard text changes only the peer endpoint host`() {
        val pinned = EndpointPins.pinnedWireGuard(wireguardText, "203.0.113.5")
        val parsed = WireGuardQuickConfig.parse(pinned)
        assertEquals("203.0.113.5:51820", parsed.endpoint)
        assertEquals(wireguardText.replace("vpn.example.org:51820", "203.0.113.5:51820"), pinned)
    }

    @Test
    fun `an IPv6 pin is bracketed in the WireGuard text`() {
        val pinned = EndpointPins.pinnedWireGuard(wireguardText, "2001:db8::5")
        assertEquals("[2001:db8::5]:51820", WireGuardQuickConfig.parse(pinned).endpoint)
    }

    @Test
    fun `Reality keeps its server name and credentials when pinned`() {
        val link = ProxyLinkConfig.parse(realityLink)
        val pinned = EndpointPins.pinnedLink(link, "203.0.113.5")
        assertEquals("203.0.113.5", pinned.host)
        assertEquals(443, pinned.port)
        assertEquals(link.credential, pinned.credential)
        val json = XrayConfiguration.json(link = pinned, access = LocalProxyAccess(1080, "u", "p"))
        assertTrue(json.contains("\"address\":\"203.0.113.5\""))
        assertTrue(json.contains("\"serverName\":\"www.example.net\""))
    }

    @Test
    fun `a TLS link without a name keeps the domain as its name`() {
        val link = ProxyLinkConfig.parse("vless://0b6a0c3e-7f1a-4a43-9d7e-4d4a4bfa1c2e@vpn.example.org:443?security=tls#phone")
        val pinned = EndpointPins.pinnedLink(link, "203.0.113.5")
        assertEquals("vpn.example.org", (pinned.credential as ProxyLinkConfig.Credential.Vless).sni)
    }

    @Test
    fun `Shadowsocks keeps its credentials and dials the address`() {
        val link = ProxyLinkConfig.parse("ss://YWVzLTI1Ni1nY206c2VjcmV0@vpn.example.org:8388#phone")
        val pinned = EndpointPins.pinnedLink(link, "2001:db8::5")
        assertEquals(link.credential, pinned.credential)
        assertEquals("[2001:db8::5]:8388", pinned.endpoint)
    }

    @Test
    fun `the endpoint is read from both kinds of configuration`() {
        assertEquals("vpn.example.org:51820", EndpointPins.endpoint(ServiceID.WIREGUARD_VPN, wireguardText))
        assertEquals("vpn.example.org:443", EndpointPins.endpoint(ServiceID.XRAY_REALITY, realityLink + "\ndns=1.1.1.1"))
        assertNull(EndpointPins.endpoint(ServiceID.SHADOWSOCKS, "not a link"))
    }
}
