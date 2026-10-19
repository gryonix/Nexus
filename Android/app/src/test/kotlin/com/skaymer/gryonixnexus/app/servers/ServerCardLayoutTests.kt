package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.ServerCardSize
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class ServerCardLayoutTests {
    /** Named servers so a failure says which one moved */
    private fun fleet(sizes: List<ServerCardSize?>): List<Deployment> =
        sizes.mapIndexed { index, size ->
            Deployment(
                id = "server-$index-id",
                name = "server-$index",
                topology = Topology.SINGLE_HOST,
                domain = "example-$index.test",
                entry = HostEndpoint(host = "203.0.113.${index + 1}", user = "root"),
                cardSize = size
            )
        }

    private fun names(rows: List<List<Deployment>>): List<List<String>> =
        rows.map { row -> row.map { it.name } }

    @Test
    fun `a server with no choice follows the app default`() {
        val unset = fleet(listOf(null))[0]
        assertEquals(ServerCardSize.WIDE, ServerCardLayout.size(unset, ServerCardSize.WIDE))
        assertEquals(ServerCardSize.COMPACT, ServerCardLayout.size(unset, ServerCardSize.COMPACT))
    }

    @Test
    fun `a server with a choice ignores the app default`() {
        val wide = fleet(listOf(ServerCardSize.WIDE))[0]
        val compact = fleet(listOf(ServerCardSize.COMPACT))[0]
        assertEquals(ServerCardSize.WIDE, ServerCardLayout.size(wide, ServerCardSize.COMPACT))
        assertEquals(ServerCardSize.COMPACT, ServerCardLayout.size(compact, ServerCardSize.WIDE))
    }

    @Test
    fun `a fleet that chose nothing is unchanged by the feature`() {
        val servers = fleet(listOf(null, null, null))
        assertEquals(
            listOf(listOf("server-0"), listOf("server-1"), listOf("server-2")),
            names(ServerCardLayout.rows(servers, ServerCardSize.WIDE))
        )
        assertEquals(
            listOf(listOf("server-0", "server-1"), listOf("server-2")),
            names(ServerCardLayout.rows(servers, ServerCardSize.COMPACT))
        )
    }

    @Test
    fun `a shrunken card is joined by the next narrow one without moving the wide ones`() {
        val servers = fleet(
            listOf(
                ServerCardSize.WIDE, ServerCardSize.COMPACT, ServerCardSize.WIDE,
                ServerCardSize.COMPACT, ServerCardSize.WIDE
            )
        )
        val rows = ServerCardLayout.rows(servers, ServerCardSize.WIDE)
        assertEquals(
            listOf(
                listOf("server-0"), listOf("server-1", "server-3"),
                listOf("server-2"), listOf("server-4")
            ),
            names(rows)
        )
        val wideRows = rows.withIndex()
            .filter { it.value.size == 1 && it.value[0].cardSize == ServerCardSize.WIDE }
        assertEquals(listOf(0, 2, 3), wideRows.map { it.index })
        assertEquals(
            listOf("server-0", "server-2", "server-4"),
            wideRows.map { it.value[0].name }
        )
    }

    @Test
    fun `an odd narrow card ends up alone on its row`() {
        val rows = ServerCardLayout.rows(
            fleet(listOf(ServerCardSize.COMPACT, ServerCardSize.COMPACT, ServerCardSize.COMPACT)),
            ServerCardSize.WIDE
        )
        assertEquals(listOf(listOf("server-0", "server-1"), listOf("server-2")), names(rows))
    }

    @Test
    fun `a wide card between two narrow ones does not break the pair`() {
        val rows = ServerCardLayout.rows(
            fleet(listOf(ServerCardSize.COMPACT, ServerCardSize.WIDE, ServerCardSize.COMPACT)),
            ServerCardSize.WIDE
        )
        assertEquals(listOf(listOf("server-0", "server-2"), listOf("server-1")), names(rows))
    }

    @Test
    fun `a row never holds more than two`() {
        val rows = ServerCardLayout.rows(
            fleet(
                listOf(
                    ServerCardSize.COMPACT, ServerCardSize.COMPACT,
                    ServerCardSize.COMPACT, ServerCardSize.COMPACT
                )
            ),
            ServerCardSize.WIDE
        )
        assertEquals(
            listOf(listOf("server-0", "server-1"), listOf("server-2", "server-3")),
            names(rows)
        )
        assertTrue(rows.all { it.size <= 2 })
    }

    @Test
    fun `every server appears exactly once`() {
        val servers = fleet(
            listOf(
                ServerCardSize.WIDE, ServerCardSize.COMPACT, null, ServerCardSize.COMPACT,
                ServerCardSize.WIDE, ServerCardSize.COMPACT, null
            )
        )
        for (fallback in ServerCardSize.entries) {
            val drawn = ServerCardLayout.rows(servers, fallback).flatten()
            assertEquals(
                servers.size, drawn.size,
                "fallback $fallback changed how many cards are drawn"
            )
            assertEquals(
                servers.map { it.id }.toSet(), drawn.map { it.id }.toSet(),
                "fallback $fallback changed the fleet"
            )
        }
    }

    @Test
    fun `a pair may form across shapes`() {
        val single = fleet(listOf(ServerCardSize.COMPACT))[0]
        val relay = Deployment(
            id = "relay-id",
            name = "relay",
            topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
            domain = "relay.test",
            entry = HostEndpoint(host = "203.0.113.9", user = "root"),
            homeWGAddress = "10.8.0.2",
            cardSize = ServerCardSize.COMPACT
        )
        assertNotEquals(
            single.nodes.size, relay.nodes.size,
            "the fixture stopped being a pair of different shapes"
        )

        val rows = ServerCardLayout.rows(listOf(single, relay), ServerCardSize.WIDE)
        assertEquals(listOf(listOf(single.id, relay.id)), rows.map { row -> row.map { it.id } })
    }
}
