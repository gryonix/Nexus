package com.skaymer.gryonixnexus.profile

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class ProxyTunnelTextTest {
    private val link = "vless://id@vpn.example.net:443?security=reality#phone"

    @Test
    fun `the link comes back untouched with its DNS`() {
        val (back, dns) = ProxyTunnelText.split(ProxyTunnelText.compose(link, listOf("9.9.9.9", "2620:fe::fe")))
        assertEquals(link, back)
        assertEquals(listOf("9.9.9.9", "2620:fe::fe"), dns)
    }

    @Test
    fun `a link stored before keeps the old DNS`() {
        assertEquals(link to listOf("1.1.1.1", "8.8.8.8"), ProxyTunnelText.split(link))
    }

    @Test
    fun `the tunnel asks IPv4 resolvers when the list has them`() {
        val cloudflare = listOf("1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001")
        assertEquals(listOf("1.1.1.1", "1.0.0.1"), ProxyTunnelText.reachableDNS(cloudflare))
        assertEquals(listOf("2620:fe::fe"), ProxyTunnelText.reachableDNS(listOf("2620:fe::fe")))
    }
}
