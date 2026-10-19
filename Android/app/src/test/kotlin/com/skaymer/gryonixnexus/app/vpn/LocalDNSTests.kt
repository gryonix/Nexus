package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.catalog.ServiceID
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** This server's own resolver in the DNS choice */
class LocalDNSTests {
    private val address = "10.53.0.53"

    @Test
    fun `it is offered only with an address and a resolver`() {
        assertTrue(LocalDNS(address, listOf(ServiceID.PIHOLE)).isOffered)
        assertFalse(LocalDNS(address).isOffered)
        assertFalse(LocalDNS("", listOf(ServiceID.PIHOLE)).isOffered)
    }

    @Test
    fun `a device on the address is recognised, and warned once the resolver is gone`() {
        val installed = LocalDNS(address, listOf(ServiceID.ADGUARD_HOME))
        assertTrue(installed.isChosen(listOf(address)))
        assertFalse(installed.isGone(listOf(address)))
        assertFalse(installed.isChosen(listOf("1.1.1.1", address)))
        val removed = LocalDNS(address)
        assertTrue(removed.isGone(listOf(address)))
        assertFalse(LocalDNS().isChosen(emptyList()))
    }

    @Test
    fun `the resolvers are named as the catalog names them`() {
        assertEquals("Pi-hole", LocalDNS(address, listOf(ServiceID.PIHOLE)).serviceNames)
        assertNull(LocalDNS(address).serviceNames)
    }

    @Test
    fun `the server's own AdGuard Home is told apart from the public AdGuard DNS`() {
        val local = LocalDNS(address, listOf(ServiceID.ADGUARD_HOME))
        val adguard = PublicDNS.all.first { it.id == "adguard" }
        assertEquals(DNSSource.YourServer("AdGuard Home"), local.source(listOf(address)))
        assertEquals(DNSSource.Public(adguard), local.source(adguard.addresses))
    }

    @Test
    fun `the server's address is its own before the server answers`() {
        assertEquals(DNSSource.YourServer(null), LocalDNS().source(listOf(LocalDNS.SERVER_ADDRESS)))
    }

    @Test
    fun `no addresses mean Cloudflare and unknown ones stay as typed`() {
        assertEquals(DNSSource.Public(PublicDNS.all.first { it.id == "cloudflare" }), LocalDNS().source(emptyList()))
        assertEquals(DNSSource.Typed(listOf("203.0.113.53")), LocalDNS().source(listOf("203.0.113.53")))
    }
}
