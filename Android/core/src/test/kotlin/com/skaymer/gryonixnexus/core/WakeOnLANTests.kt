package com.skaymer.gryonixnexus.core

import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class WakeOnLANTests {
    private val mac = "aa:bb:cc:dd:ee:ff"

    @Test
    fun `every usual spelling of a MAC is the same six bytes`() {
        val expected = byteArrayOf(
            0xAA.toByte(), 0xBB.toByte(), 0xCC.toByte(),
            0xDD.toByte(), 0xEE.toByte(), 0xFF.toByte(),
        )
        for (spelling in listOf("aa:bb:cc:dd:ee:ff", "AA-BB-CC-DD-EE-FF", "aabb.ccdd.eeff", "AABBCCDDEEFF")) {
            assertTrue(expected.contentEquals(WakeOnLAN.macBytes(spelling)), spelling)
        }
    }

    @Test
    fun `a half-typed address is not a MAC`() {
        for (text in listOf("", "aa:bb", "aa:bb:cc:dd:ee", "aa:bb:cc:dd:ee:ff:00", "zz:bb:cc:dd:ee:ff", "aabbccddeef")) {
            assertNull(WakeOnLAN.macBytes(text), text)
        }
    }

    @Test
    fun `a stored address is written one way`() {
        assertEquals(mac, WakeOnLAN.normalised("AA-BB-CC-DD-EE-FF"))
        assertEquals(mac, WakeOnLAN.normalised("aabbccddeeff"))
        assertNull(WakeOnLAN.normalised("not a mac"))
    }

    /** Six 0xFF, then the address sixteen times: 102 bytes */
    @Test
    fun `the magic packet is six ones and sixteen copies`() {
        val packet = WakeOnLAN.magicPacket(mac)!!
        assertEquals(102, packet.size)
        for (index in 0 until 6) assertEquals(0xFF.toByte(), packet[index], "byte $index")
        val address = byteArrayOf(
            0xAA.toByte(), 0xBB.toByte(), 0xCC.toByte(),
            0xDD.toByte(), 0xEE.toByte(), 0xFF.toByte(),
        )
        for (copy in 0 until 16) {
            val start = 6 + copy * 6
            assertTrue(
                address.contentEquals(packet.copyOfRange(start, start + 6)),
                "copy $copy of the address is not the address",
            )
        }
    }

    @Test
    fun `no packet for something that is not an address`() {
        assertNull(WakeOnLAN.magicPacket("aa:bb:cc"))
    }

    @Test
    fun `the broadcast address is the subnet's own`() {
        assertEquals("192.168.1.255", WakeOnLAN.broadcastAddress("192.168.1.40"))
        assertEquals("10.0.0.255", WakeOnLAN.broadcastAddress("10.0.0.2"))
    }

    /**
     * **A hostname has no broadcast address** — a machine that is off cannot be
     * resolved, so there is nothing to derive a subnet from.
     */
    @Test
    fun `a hostname has no broadcast address`() {
        for (host in listOf("server.example.com", "localhost", "192.168.1", "192.168.1.999", "")) {
            assertNull(WakeOnLAN.broadcastAddress(host), host)
        }
    }

    @Test
    fun `the peer command writes the packet into the broadcast address`() {
        val command = WakeOnLAN.command(mac, "192.168.1.255")!!
        assertTrue(command.startsWith("python3 -c 'import socket"), command)
        assertTrue(command.contains("SO_BROADCAST"), "a broadcast needs the option, or Linux refuses it")
        assertTrue(command.contains("|| bash -c 'printf \""), command)
        assertTrue(command.endsWith("> /dev/udp/192.168.1.255/9'"), command)
        assertEquals(102, command.split("\\x").size - 1)
        assertTrue(command.contains("bytes.fromhex(\"" + "ff".repeat(6)))
        assertTrue(command.contains("\\xff".repeat(6)), "the packet does not start with six 0xFF bytes")
    }

    @Test
    fun `no peer command without both halves`() {
        assertNull(WakeOnLAN.command("aa:bb", "192.168.1.255"))
        assertNull(WakeOnLAN.command(mac, "server.example.com"))
    }
}
