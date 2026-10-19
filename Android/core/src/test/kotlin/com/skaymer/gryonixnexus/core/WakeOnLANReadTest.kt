package com.skaymer.gryonixnexus.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class WakeOnLANReadTest {
    @Test
    fun readGivesTheMacAndTheBroadcast() {
        val read = WakeOnLAN.parseRead("E0:3F:49:AE:F3:D5\n192.168.178.255\n")
        assertEquals("e0:3f:49:ae:f3:d5", read?.mac)
        assertEquals("192.168.178.255", read?.broadcast)
        assertNull(WakeOnLAN.parseRead("e0:3f:49:ae:f3:d5\n")?.broadcast)
        assertNull(WakeOnLAN.parseRead("no device\n"))
    }

    @Test
    fun thereIsAlwaysSomewhereToSend() {
        assertEquals("10.0.0.255", WakeOnLAN.broadcast("10.0.0.255", "draco.local", null))
        assertEquals("192.168.1.255", WakeOnLAN.broadcast(null, "192.168.1.20", null))
        assertEquals("192.168.178.255", WakeOnLAN.broadcast(null, "draco.local", "192.168.178.40"))
        assertEquals("255.255.255.255", WakeOnLAN.broadcast(null, "draco.local", null))
    }

    @Test
    fun theReadCommandMatchesSwift() {
        assertEquals(
            "dev=\$(ip route show default | awk '{print \$5; exit}'); cat /sys/class/net/\$dev/address; " +
                "ip -4 -o addr show dev \"\$dev\" | awk '{for(i=1;i<=NF;i++) if(\$i==\"brd\"){print \$(i+1); exit}}'",
            WakeOnLAN.READ_COMMAND,
        )
    }
}
