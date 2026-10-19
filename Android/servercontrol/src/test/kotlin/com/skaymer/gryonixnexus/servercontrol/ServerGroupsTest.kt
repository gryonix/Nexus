package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.Topology
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class ServerGroupsTest {
    private fun deployment(name: String, tags: List<String>) = Deployment(
        id = name,
        name = name,
        topology = Topology.SINGLE_HOST,
        domain = "example.com",
        entry = HostEndpoint(host = "203.0.113.10", user = "root"),
        tags = tags,
    )

    @Test
    fun `the strip is built from what the fleet says`() {
        val fleet = listOf(deployment("a", listOf("prod")), deployment("b", listOf("lab", "prod")))
        assertEquals(listOf("lab", "prod"), ServerGroups.known(fleet))
        assertEquals(listOf("prod"), ServerGroups.known(listOf(deployment("a", listOf("prod")))))
        assertEquals(emptyList<String>(), ServerGroups.known(listOf(deployment("a", emptyList()))))
    }

    @Test
    fun `membership ignores case`() {
        val fleet = listOf(deployment("a", listOf("Prod")))
        assertEquals(1, ServerGroups.members("prod", fleet).size)
        assertEquals(listOf("lab"), ServerGroups.setting(false, "prod", listOf("Prod", "lab")))
        // Adding what is already there does not add it twice.
        assertEquals(listOf("prod"), ServerGroups.setting(true, "prod", listOf("Prod")))
    }

    @Test
    fun `a name is what is left after the spaces`() {
        assertEquals("lab", ServerGroups.clean("  lab "))
        assertNull(ServerGroups.clean("   "))
        assertNull(ServerGroups.clean(""))
    }

    /** The selection is the price of storing no group list */
    @Test
    fun `a selection whose group is gone falls back to all`() {
        val fleet = listOf(deployment("a", listOf("prod")))
        assertEquals("prod", ServerGroups.reachable("prod", fleet))
        assertNull(ServerGroups.reachable("lab", fleet))
        assertNull(ServerGroups.reachable(null, fleet))
    }
}
