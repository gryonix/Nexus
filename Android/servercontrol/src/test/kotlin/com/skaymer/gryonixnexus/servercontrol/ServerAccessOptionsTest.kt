package com.skaymer.gryonixnexus.servercontrol

import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ServerAccessOptionsTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `everything survives a round trip`() {
        val options = ServerAccessOptions(
            agentForwarding = true,
            sftpDirectory = "/srv",
            bastion = BastionHop(manual = HostEndpoint("jump.example", 2222, "ops")),
            fallback = FallbackAddress("203.0.113.9", 22, BastionHop(fleetServerID = "abc")),
        )
        val text = json.encodeToString(ServerAccessOptions.serializer(), options)
        assertEquals(options, json.decodeFromString(ServerAccessOptions.serializer(), text))
    }

    /** A record written before a field existed must still load */
    @Test
    fun `an older record decodes as nothing chosen`() {
        val options = json.decodeFromString(ServerAccessOptions.serializer(), "{}")
        assertEquals(ServerAccessOptions.NONE, options)
        assertTrue(options.isEmpty)
    }

    @Test
    fun `an empty host falls back to the primary address`() {
        val primary = HostEndpoint("203.0.113.4", 22, "root")
        val fallback = FallbackAddress(bastion = BastionHop(fleetServerID = "abc"))
        assertEquals(primary, fallback.endpoint(primary))
    }

    @Test
    fun `a typed address replaces the host but keeps the account`() {
        val primary = HostEndpoint("203.0.113.4", 22, "root")
        val resolved = FallbackAddress(host = " 198.51.100.7 ").endpoint(primary)
        assertEquals("198.51.100.7", resolved.host)
        assertEquals(22, resolved.port)
        assertEquals("root", resolved.user)
    }

    @Test
    fun `a fallback that changes nothing is not usable`() {
        assertFalse(FallbackAddress().isUsable)
        assertFalse(FallbackAddress(host = "   ").isUsable)
        assertTrue(FallbackAddress(host = "198.51.100.7").isUsable)
        assertTrue(FallbackAddress(bastion = BastionHop(fleetServerID = "abc")).isUsable)
    }

    @Test
    fun `a hop that names nothing is not a hop`() {
        assertFalse(BastionHop().isUsable)
        assertTrue(BastionHop(fleetServerID = "abc").isUsable)
        assertTrue(BastionHop(manual = HostEndpoint("jump.example", 22, "ops")).isUsable)
        assertFalse(BastionHop(manual = HostEndpoint("", 22, "ops")).isUsable)
    }
}
