package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.Topology
import kotlin.test.assertEquals
import kotlin.test.assertNull
import org.junit.jupiter.api.Test

class KnownHostsTest {
    private val deployment = Deployment(
        id = "S-1", name = "orion", topology = Topology.SINGLE_HOST, domain = "example.net",
        entry = HostEndpoint(host = "203.0.113.5", port = 2222, user = "root"), services = emptySet(),
    )

    @Test
    fun `the fingerprint is the SHA256 of the key blob without padding`() {
        val key = KnownHosts.describe("ssh-ed25519 aGVsbG8=")
        assertEquals("ssh-ed25519", key?.keyType)
        assertEquals("SHA256:LPJNul+wow4m6DsqxbninhsWHlwfp0JecwQzYpOLmCQ", key?.fingerprint)
    }

    @Test
    fun `garbage is not a key`() {
        assertNull(KnownHosts.describe("unreadable"))
        assertNull(KnownHosts.describe("ssh-rsa !!!"))
    }

    @Test
    fun `only machines with a pin are listed`() {
        val rows = KnownHosts.entries(deployment) { "ssh-ed25519 aGVsbG8=" }
        assertEquals(1, rows.size)
        assertEquals("203.0.113.5:2222", rows[0].endpoint)
        assertEquals(0, KnownHosts.entries(deployment) { null }.size)
    }

    @Test
    fun `jump host rows come from their endpoints`() {
        val rows = KnownHosts.bastionEntries(deployment, listOf("198.51.100.7:22", "198.51.100.8:22")) {
            if (it.endsWith("7:22")) "ssh-rsa aGVsbG8=" else null
        }
        assertEquals(listOf("198.51.100.7:22"), rows.map { it.endpoint })
    }
}
