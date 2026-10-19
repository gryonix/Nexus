package com.skaymer.gryonixnexus.app.dns

import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** Dynamic DNS */
class DynamicDNSViewModelTests {
    private fun server(usesAgent: Boolean = true) = Deployment(
        id = "S-1",
        name = "middle",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
        services = emptySet(),
        usesAgent = usesAgent,
    )

    @Test
    fun `only an agent server can keep its own records current`() {
        assertTrue(DynamicDNSViewModel.canManage(server(usesAgent = true)))
        assertFalse(DynamicDNSViewModel.canManage(server(usesAgent = false)))
        assertFalse(
            DynamicDNSViewModel.canManage(server(usesAgent = true), agentTransportAvailable = false)
        )
    }

    @Test
    fun `names are one per line, trimmed, and blank lines are not names`() {
        assertEquals(
            listOf("home.example.test", "vpn.example.test"),
            DynamicDNSViewModel.names("home.example.test\n\n  vpn.example.test  \n"),
        )
        assertTrue(DynamicDNSViewModel.names("   \n\n").isEmpty())
    }

    @Test
    fun `a first setup needs the token and a later edit does not`() {
        val names = listOf("home.example.test")
        assertFalse(
            DynamicDNSViewModel.canSave("example.test", names, token = "", hasStoredToken = false)
        )
        assertTrue(
            DynamicDNSViewModel.canSave("example.test", names, token = "cf-token", hasStoredToken = false)
        )
        assertTrue(
            DynamicDNSViewModel.canSave("example.test", names, token = "", hasStoredToken = true)
        )
    }

    @Test
    fun `a zone or a name list nobody filled in cannot be saved`() {
        assertFalse(
            DynamicDNSViewModel.canSave("  ", listOf("home.example.test"), "t", hasStoredToken = true)
        )
        assertFalse(
            DynamicDNSViewModel.canSave("example.test", emptyList(), "t", hasStoredToken = true)
        )
    }

    @Test
    fun `nothing is claimed about the host before it answers`() {
        assertNull(DynamicDNSScreenState().state)
        assertFalse(DynamicDNSScreenState().isWorking)
    }
}
