package com.skaymer.gryonixnexus.app.terminal

import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HomePathChoice
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.transport.TerminalEndpoint
import com.skaymer.gryonixnexus.transport.TerminalEndpoint.Kind
import com.skaymer.gryonixnexus.transport.TerminalLogin
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TerminalRoutesTests {
    private val login = TerminalLogin("root", TerminalLogin.Secret.Password("x"))
    private val hop = TerminalEndpoint.Hop("203.0.113.4", 22, null, login)

    @Test
    fun `the chosen path decides which routes a machine behind the VPS has`() {
        val relayed = TerminalEndpoint("10.8.0.2", 22, parent = hop)
        fun kinds(choice: HomePathChoice) = TerminalRoutes.behindVPS(relayed, "192.168.1.5", choice).map { it.kind }
        assertEquals(listOf(Kind.LOCAL_NETWORK, Kind.RELAY, Kind.TUNNEL_ADDRESS), kinds(HomePathChoice.AUTOMATIC))
        assertEquals(listOf(Kind.RELAY, Kind.TUNNEL_ADDRESS), kinds(HomePathChoice.THROUGH_VPS))
        assertEquals(listOf(Kind.LOCAL_NETWORK), kinds(HomePathChoice.LOCAL_NETWORK))
        assertTrue(TerminalRoutes.behindVPS(relayed, null, HomePathChoice.LOCAL_NETWORK).isEmpty())
    }

    @Test
    fun `the row reports the choice or the route that worked last`() {
        assertEquals(HomePathChoice.THROUGH_VPS, TerminalRoutes.pathInUse(HomePathChoice.AUTOMATIC, null))
        assertEquals(HomePathChoice.LOCAL_NETWORK, TerminalRoutes.pathInUse(HomePathChoice.AUTOMATIC, "LOCAL_NETWORK"))
        assertEquals(HomePathChoice.THROUGH_VPS, TerminalRoutes.pathInUse(HomePathChoice.THROUGH_VPS, "LOCAL_NETWORK"))
    }

    @Test
    fun `a relayed machine goes through its relay then straight to its tunnel address`() {
        val routes = TerminalRoutes.relayed(TerminalEndpoint("10.8.0.2", 22, parent = hop))
        assertEquals(listOf(Kind.RELAY, Kind.TUNNEL_ADDRESS), routes.map { it.kind })
        assertEquals(hop, routes[0].parent)
        assertNull(routes[1].parent)
        assertEquals(TerminalRoutes.LOCAL_TIMEOUT_MS, routes[1].connectTimeoutMs)
    }

    @Test
    fun `the entry tries its fallback address second`() {
        val routes = TerminalRoutes.entry(
            TerminalEndpoint("203.0.113.4", 22),
            TerminalEndpoint("198.51.100.7", 2222),
        )
        assertEquals(listOf(Kind.DIRECT, Kind.FALLBACK_ADDRESS), routes.map { it.kind })
        assertEquals(1, TerminalRoutes.entry(TerminalEndpoint("203.0.113.4", 22), null).size)
    }

    @Test
    fun `the route that worked last goes first`() {
        val routes = TerminalRoutes.relayed(TerminalEndpoint("10.8.0.2", 22, parent = hop))
        assertEquals(routes, TerminalRoutes.ordered(routes, null))
        assertEquals(listOf(Kind.TUNNEL_ADDRESS, Kind.RELAY), TerminalRoutes.ordered(routes, "TUNNEL_ADDRESS").map { it.kind })
        assertEquals(routes, TerminalRoutes.ordered(routes, "FALLBACK_ADDRESS"))
        assertEquals(routes, TerminalRoutes.ordered(routes, "nonsense"))
    }

    @Test
    fun `each machine remembers its own route`() {
        assertEquals("terminal.route.d.entry", TerminalRoutes.memoryKey("d", null))
        assertEquals("terminal.route.d.n", TerminalRoutes.memoryKey("d", "n"))
    }

    @Test
    fun `private addresses are the ones a tunnel reaches`() {
        for (host in listOf("10.8.0.2", "192.168.1.5", "172.20.0.4", "100.64.1.2", "fd00::1", "nas.local")) {
            assertTrue(TerminalRoutes.isPrivate(host), host)
        }
        for (host in listOf("203.0.113.4", "172.32.0.1", "example.com", "8.8.8.8", "fdroid.example")) {
            assertFalse(TerminalRoutes.isPrivate(host), host)
        }
    }

    private fun pair() = Deployment(
        id = "00000000-0000-0000-0000-0000000000B2",
        name = "pair",
        topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.10", user = "root"),
        homeWGAddress = "10.8.0.2",
    )

    private fun detours(host: String, directID: String = "direct") = TerminalRoutes.homeDetours(
        target = TerminalEndpoint(host, 22),
        directID = directID,
        fleet = listOf(pair()),
        endpoint = { server, node ->
            TerminalViewModel.endpoint(server, node, pin = { null }, appLogin = { login })
        },
        login = { _, _ -> login },
    )

    @Test
    fun `the home machine by its tunnel address goes through the relay`() {
        val routes = detours("10.8.0.2")
        assertEquals(listOf(Kind.RELAY, Kind.TUNNEL_ADDRESS), routes.map { it.kind })
        assertEquals(listOf("203.0.113.10"), routes[0].hops.map { it.host })
    }

    @Test
    fun `a neighbour on the home network is reached through the home machine`() {
        val routes = detours("192.168.1.40")
        assertEquals(listOf("203.0.113.10", "10.8.0.2"), routes.single().hops.map { it.host })
        assertEquals("203.0.113.10:22 → 10.8.0.2:22 → 192.168.1.40:22", routes.single().summary)
    }

    @Test
    fun `a name on the home network is asked of the home machine`() {
        assertEquals("orion.local", detours("orion.local").single().host)
    }

    @Test
    fun `public addresses and the servers own machines get no detour`() {
        assertTrue(detours("203.0.113.50").isEmpty())
        assertTrue(detours("10.8.0.2", directID = pair().id).isEmpty())
    }

    private fun chosen(host: String, via: TerminalVia) = TerminalRoutes.chosen(
        target = TerminalEndpoint(host, 22),
        via = via,
        fleet = listOf(pair()),
        endpoint = { server, node ->
            TerminalViewModel.endpoint(server, node, pin = { null }, appLogin = { login })
        },
        login = { _, _ -> login },
    )

    @Test
    fun `a chosen server is the jump host for any address`() {
        val routes = chosen("192.168.1.40", TerminalVia(pair().id))
        assertEquals(listOf(Kind.RELAY), routes.map { it.kind })
        assertEquals(listOf("203.0.113.10"), routes.single().hops.map { it.host })
    }

    @Test
    fun `a chosen home machine is reached through its server`() {
        val home = pair().nodes[1]
        val routes = chosen("192.168.1.40", TerminalVia(pair().id, home.id))
        assertEquals(listOf("203.0.113.10", "10.8.0.2"), routes.single().hops.map { it.host })
    }

    @Test
    fun `a server that is gone gives no route`() {
        assertTrue(chosen("192.168.1.40", TerminalVia("gone")).isEmpty())
    }

    @Test
    fun `every machine with an address is offered`() {
        val choices = TerminalRoutes.viaChoices(listOf(pair()))
        assertEquals(2, choices.size)
        assertEquals("pair", choices.first().second)
        assertNull(choices.first().first.node)
    }

    @Test
    fun `a failed direct try at a home address says how to go through a server`() {
        val text = TerminalRoutes.describe(
            RuntimeException("Host is down"),
            listOf(TerminalEndpoint("192.168.1.40", 22)),
            title = { it.name },
            hint = "HINT",
        )
        assertEquals("DIRECT (192.168.1.40:22): Host is down\nHINT", text)
    }

    @Test
    fun `every tried way is named`() {
        val failed = com.skaymer.gryonixnexus.transport.TerminalRoutesFailed(
            listOf(TerminalEndpoint("192.168.1.40", 22) to "Host is down", TerminalEndpoint("10.8.0.2", 22, kind = Kind.RELAY) to "timed out"),
        )
        val lines = TerminalRoutes.describe(failed, emptyList(), title = { it.name }, hint = "HINT").lines()
        assertEquals(2, lines.size)
        assertTrue(lines[1].startsWith("RELAY"))
    }
}
