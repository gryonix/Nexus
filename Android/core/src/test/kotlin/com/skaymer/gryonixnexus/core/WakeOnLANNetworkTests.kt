package com.skaymer.gryonixnexus.core

import kotlin.test.assertEquals
import kotlin.test.assertNull
import org.junit.jupiter.api.Test

class WakeOnLANNetworkTests {
    private val home = WakeOnLAN.DeviceAddress("192.168.178.23", 24)
    private val cellular = WakeOnLAN.DeviceAddress("10.132.7.9", 32)
    private val tunnel = WakeOnLAN.DeviceAddress("10.66.66.2", 32)

    @Test
    fun `a phone on the home Wi-Fi shares the machine's network`() {
        assertEquals(true, WakeOnLAN.sharesNetwork(listOf(home), "192.168.178.100", null))
        assertEquals(true, WakeOnLAN.sharesNetwork(listOf(cellular, home), "192.168.178.100", null))
    }

    @Test
    fun `a phone on mobile data or another Wi-Fi does not`() {
        assertEquals(false, WakeOnLAN.sharesNetwork(listOf(cellular), "192.168.178.100", null))
        val cafe = WakeOnLAN.DeviceAddress("192.168.1.40", 24)
        assertEquals(false, WakeOnLAN.sharesNetwork(listOf(cafe, tunnel), "192.168.178.100", null))
        assertEquals(false, WakeOnLAN.sharesNetwork(emptyList(), "192.168.178.100", null))
    }

    @Test
    fun `the stored broadcast answers when only a name is known`() {
        assertEquals(true, WakeOnLAN.sharesNetwork(listOf(home), null, "192.168.178.255"))
        assertEquals(false, WakeOnLAN.sharesNetwork(listOf(cellular), null, "192.168.178.255"))
        assertEquals(true, WakeOnLAN.sharesNetwork(listOf(WakeOnLAN.DeviceAddress("10.0.4.7", 16)), null, "10.0.255.255"))
    }

    @Test
    fun `nothing known about the machine is no answer`() {
        assertNull(WakeOnLAN.sharesNetwork(listOf(home), null, null))
        assertNull(WakeOnLAN.sharesNetwork(listOf(home), "draco.local", "255.255.255.255"))
    }
}
