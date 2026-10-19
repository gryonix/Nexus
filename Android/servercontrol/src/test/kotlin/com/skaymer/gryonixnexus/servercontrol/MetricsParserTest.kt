package com.skaymer.gryonixnexus.servercontrol

import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class SysctlParserTest {
    @Test
    fun `forwarding on and off`() {
        assertTrue(SysctlParser.parseIPForwarding("net.ipv4.ip_forward = 1\n"))
        assertFalse(SysctlParser.parseIPForwarding("net.ipv4.ip_forward = 0"))
    }

    @Test
    fun `an answer that is not the setting is a parse failure, not a false`() {
        assertFailsWith<ServerControlError.ParseFailure> {
            SysctlParser.parseIPForwarding("permission denied")
        }
    }
}

class PingParserTest {
    @Test
    fun `the statistics line is found among the ping chatter`() {
        val output = """
            PING 1.2.3.4 (1.2.3.4) 56(84) bytes of data.
            64 bytes from 1.2.3.4: icmp_seq=1 ttl=64 time=0.3 ms

            --- 1.2.3.4 ping statistics ---
            4 packets transmitted, 4 received, 0% packet loss, time 3004ms
        """.trimIndent()
        val result = PingParser.parse(output)
        assertEquals(4, result.transmitted)
        assertEquals(4, result.received)
        assertTrue(result.isAlive)
    }

    @Test
    fun `nothing received is not alive`() {
        val result = PingParser.parse("1 packets transmitted, 0 received, 100% packet loss, time 0ms")
        assertEquals(0, result.received)
        assertFalse(result.isAlive)
    }

    /** busybox/iputils repeats the word: "1 packets received" */
    @Test
    fun `the busybox wording parses too`() {
        assertEquals(1, PingParser.parse("1 packets transmitted, 1 packets received, 0% packet loss").received)
    }

    @Test
    fun `no statistics at all throws`() {
        assertFailsWith<ServerControlError.ParseFailure> { PingParser.parse("ping: unknown host") }
    }
}

class WGShowParserTest {
    private val sample = """
        interface: wg0
          public key: IFpUB1t5eqcpF4aYKsRhwc0vJnDPzM0hE2NGZ0i+HFY=
          private key: (hidden)
          listening port: 51820

        peer: cyfBMbaJ6kgnDYjio6xqWikJTEQAbnHnLEwGFdBpp0Q=
          endpoint: 203.0.113.4:51820
          allowed ips: 10.8.0.2/32
          latest handshake: 1 minute, 12 seconds ago
          transfer: 1.21 MiB received, 3.45 MiB sent
    """.trimIndent()

    @Test
    fun `the interface block is read, private key and all`() {
        val status = WGShowParser.parse(sample)
        assertEquals("wg0", status.`interface`.name)
        assertEquals("IFpUB1t5eqcpF4aYKsRhwc0vJnDPzM0hE2NGZ0i+HFY=", status.`interface`.publicKey)
        assertEquals(51820, status.`interface`.listeningPort)
    }

    @Test
    fun `a fresh peer keeps its endpoint whole`() {
        val status = WGShowParser.parse(sample)
        assertEquals(1, status.peers.size)
        val peer = status.peers.first()
        assertEquals("203.0.113.4:51820", peer.endpoint)
        assertEquals(listOf("10.8.0.2/32"), peer.allowedIPs)
        assertEquals(HealthLevel.OK, peer.freshness)
    }

    @Test
    fun `a stale peer is a warning even though its text says minutes`() {
        val stale = sample.replace("1 minute, 12 seconds ago", "3 hours, 2 minutes ago")
        assertEquals(HealthLevel.WARNING, WGShowParser.parse(stale).peers.first().freshness)
    }

    @Test
    fun `a peer that never handshook is critical`() {
        val never = """
            interface: wg0
              listening port: 51820

            peer: abc=
              allowed ips: 10.8.0.2/32
        """.trimIndent()
        assertEquals(HealthLevel.CRITICAL, WGShowParser.parse(never).peers.first().freshness)
    }

    @Test
    fun `fields do not leak between peers`() {
        val two = sample + "\n\npeer: second+key=\n  allowed ips: 10.8.0.3/32"
        val status = WGShowParser.parse(two)
        assertEquals(2, status.peers.size)
        assertNull(status.peers[1].endpoint)
        assertNull(status.peers[1].latestHandshake)
        assertEquals(HealthLevel.CRITICAL, status.peers[1].freshness)
    }

    @Test
    fun `output with no interface throws`() {
        assertFailsWith<ServerControlError.ParseFailure> { WGShowParser.parse("") }
    }
}

class DFParserTest {
    @Test
    fun `every mount row becomes a mount`() {
        val output = """
            Mounted on     1B-blocks        Used Use%
            /            41678012416 12345678901  30%
            /boot          503316480    52428800  11%
        """.trimIndent()
        val mounts = DFParser.parse(output)
        assertEquals(2, mounts.size)
        assertEquals("/", mounts[0].target)
        assertEquals(41_678_012_416L, mounts[0].sizeBytes)
        assertEquals(12_345_678_901L, mounts[0].usedBytes)
        assertEquals(30, mounts[0].usedPercent)
        assertEquals("/boot", mounts[1].target)
        assertEquals(52_428_800.0 / 503_316_480.0, mounts[1].usedFraction, 0.0001)
    }

    @Test
    fun `a mount point with a space survives`() {
        val output = """
            Mounted on     1B-blocks        Used Use%
            /mnt/my disk   503316480    52428800  11%
        """.trimIndent()
        assertEquals("/mnt/my disk", DFParser.parse(output).first().target)
    }

    @Test
    fun `empty output throws`() {
        assertFailsWith<ServerControlError.ParseFailure> { DFParser.parse("") }
    }
}

class FreeParserTest {
    @Test
    fun `the Mem and Swap rows are read, the header is not`() {
        val output = """
                           total        used        free      shared  buff/cache   available
            Mem:      8201928704  1234567890  5000000000    10000000  1967360814  6600000000
            Swap:      104853504    12345678    92507826
        """.trimIndent()
        val usage = FreeParser.parse(output)
        assertEquals(8_201_928_704L, usage.memTotalBytes)
        assertEquals(1_234_567_890L, usage.memUsedBytes)
        assertEquals(104_853_504L, usage.swapTotalBytes)
        assertEquals(12_345_678L, usage.swapUsedBytes)
    }

    @Test
    fun `no Mem row throws`() {
        assertFailsWith<ServerControlError.ParseFailure> { FreeParser.parse("total used free") }
    }
}
