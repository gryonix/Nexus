package com.skaymer.gryonixnexus.core

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

/** A port of DomainTests.swift, case for case */
class DomainTest {
    @Test
    fun `valid domains`() {
        assertEquals("example.com", Domain.of("example.com").name)
        assertEquals("sub.example.co.uk", Domain.of("sub.example.co.uk").name)
        assertEquals("xn--80ak6aa92e.com", Domain.of("xn--80ak6aa92e.com").name)
    }

    @Test
    fun `normalization`() {
        assertEquals("example.com", Domain.of("  Example.COM \n").name)
    }

    @Test
    fun `invalid domains`() {
        for (candidate in listOf("", "example", "exa mple.com", "-example.com", "example-.com",
                                 "example.c", "example.123", ".example.com", "example..com")) {
            assertThrows<ValidationError.InvalidDomain>("must throw for \"$candidate\"") {
                Domain.of(candidate)
            }
        }
    }
}

class NetworkAddressTest {
    @Test
    fun `valid ipv4`() {
        assertEquals(NetworkAddress.IPv4("203.0.113.10"), NetworkAddress.parse("203.0.113.10"))
        assertEquals(NetworkAddress.IPv4("10.8.0.1"), NetworkAddress.parse("10.8.0.1"))
        assertEquals(NetworkAddress.IPv4("0.0.0.0"), NetworkAddress.parse("0.0.0.0"))
    }

    @Test
    fun `valid ipv6`() {
        assertEquals(NetworkAddress.IPv6("2001:db8::1"), NetworkAddress.parse("2001:db8::1"))
        assertEquals("::1", NetworkAddress.parse("::1").value)
    }

    @Test
    fun `local only accepts a hostname`() {
        assertEquals(NetworkAddress.Hostname("orion.local"), NetworkAddress.localOnly("orion.local"))
        assertEquals(NetworkAddress.Hostname("orion.local"), NetworkAddress.localOnly("  ORION.local "))
        assertEquals("server.lan", NetworkAddress.localOnly("server.lan").value)
        assertEquals(NetworkAddress.IPv4("192.168.1.50"), NetworkAddress.localOnly("192.168.1.50"))
        assertTrue(NetworkAddress.localOnly("192.168.1.50").isIPv4)
        assertFalse(NetworkAddress.localOnly("orion.local").isIPv4)
    }

    @Test
    fun `strict parser still rejects a hostname`() {
        assertThrows<ValidationError.InvalidAddress> { NetworkAddress.parse("orion.local") }
    }

    @Test
    fun `local only still rejects nonsense`() {
        for (candidate in listOf("", "orion", "not a host", "-bad.local", "256.0.0.1.2")) {
            assertThrows<ValidationError.InvalidAddress>("must throw for \"$candidate\"") {
                NetworkAddress.localOnly(candidate)
            }
        }
    }

    @Test
    fun `invalid addresses`() {
        for (candidate in listOf("", "256.0.0.1", "1.2.3", "1.2.3.4.5", "01.2.3.4", "a.b.c.d", "10.8.0")) {
            assertThrows<ValidationError.InvalidAddress>("must throw for \"$candidate\"") {
                NetworkAddress.parse(candidate)
            }
        }
    }
}
