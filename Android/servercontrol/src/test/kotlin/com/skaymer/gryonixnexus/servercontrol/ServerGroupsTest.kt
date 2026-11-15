package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.Topology
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
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

    @Test
    fun `groups without a place keep their name order`() {
        assertEquals(listOf("Home", "Lab", "Work"), ServerGroups.ordered(listOf("Work", "Home", "Lab"), emptyList()))
    }

    @Test
    fun `placed groups come first in their place order`() {
        assertEquals(listOf("Work", "Lab", "Home"), ServerGroups.ordered(listOf("Work", "Home", "Lab"), listOf("Work", "Lab")))
    }

    @Test
    fun `moving right swaps with the neighbour and the edges stay`() {
        assertEquals(listOf("Lab", "Home", "Work"), ServerGroups.moving("Home", 1, listOf("Home", "Lab", "Work"), emptyList()))
        assertNull(ServerGroups.moving("Home", -1, listOf("Home", "Lab"), emptyList()))
        assertNull(ServerGroups.moving("Lab", 1, listOf("Home", "Lab"), emptyList()))
    }

    @Test
    fun `a move keeps the places of groups not shown`() {
        assertEquals(listOf("Lab", "Home", "Old"), ServerGroups.moving("Lab", -1, listOf("Home", "Lab"), listOf("Old", "Home", "Lab")))
    }

    @Test
    fun `rename delete and import follow the group`() {
        assertEquals(listOf("Home", "Garage"), ServerGroups.renaming("lab", "Garage", listOf("Home", "Lab")))
        assertEquals(listOf("Lab"), ServerGroups.removing("HOME", listOf("Home", "Lab")))
        assertEquals(listOf("Home", "Lab", "Office"), ServerGroups.adopting(listOf("lab", "Office"), listOf("Home", "Lab")))
        assertEquals(listOf("Home", "Lab two"), ServerGroups.parse(ServerGroups.format(listOf("Home", "Lab two"))))
        assertEquals(emptyList<String>(), ServerGroups.parse(null))
    }

    private fun transfer(name: String, tags: List<String>) = Json.parseToJsonElement(
        """{"version":1,"deployment":{"id":"$name","name":"$name","tags":[${tags.joinToString(",") { "\"$it\"" }}]}}""",
    )

    @Test
    fun `a group file keeps only its own groups and round trips`() {
        val bundle = ServerGroupBundle.make(listOf("Home"), listOf(transfer("mail", listOf("Home", "Work"))))
        val text = bundle.encoded()
        assertTrue(ServerGroupBundle.isBundle(text))
        assertFalse(ServerGroupBundle.isBundle("""{"version":1,"deployment":{}}"""))
        val decoded = ServerGroupBundle.decode(text)
        assertEquals(listOf("Home"), decoded.groups)
        val tags = decoded.servers.single().jsonObject["deployment"]!!.jsonObject["tags"]!!.jsonArray
        assertEquals(listOf("Home"), tags.map { it.jsonPrimitive.content })
    }

    @Test
    fun `the apple app's group file reads here`() {
        val apple = """
        {
          "groups" : [ "Lab", "Home" ],
          "kind" : "gryonixgroups",
          "servers" : [ { "deployment" : { "id" : "A", "name" : "cloud", "tags" : [ "Lab" ] }, "hostKeyPins" : { }, "reports" : [ ], "version" : 1, "wireGuardSeeds" : { } } ],
          "version" : 1
        }
        """.trimIndent()
        val decoded = ServerGroupBundle.decode(apple)
        assertEquals(listOf("Lab", "Home"), decoded.groups)
        assertEquals("cloud", (decoded.servers.single() as JsonObject)["deployment"]!!.jsonObject["name"]!!.jsonPrimitive.content)
    }

    @Test
    fun `a file from a newer app is refused`() {
        assertThrows(ServerGroupBundle.UnsupportedVersion::class.java) {
            ServerGroupBundle.decode("""{"kind":"gryonixgroups","version":2,"groups":[],"servers":[]}""")
        }
        assertThrows(ServerGroupBundle.UnsupportedVersion::class.java) {
            ServerGroupBundle.decode("""{"kind":"gryonixgroups","version":1,"groups":[],"servers":[{"version":2}]}""")
        }
    }

    @Test
    fun `members of several groups are listed once`() {
        val shared = deployment("mail", listOf("Home", "Work"))
        val other = deployment("vpn", listOf("Lab"))
        assertEquals(listOf("mail"), ServerGroups.membersOfAny(listOf("home", "Work"), listOf(shared, other)).map { it.id })
    }
}
