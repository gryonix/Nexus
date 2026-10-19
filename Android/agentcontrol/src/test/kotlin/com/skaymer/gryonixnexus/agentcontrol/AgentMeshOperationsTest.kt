package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import gryonixnexusd.v1.MeshAuthKey
import gryonixnexusd.v1.MeshNameList
import gryonixnexusd.v1.MeshNodeList
import gryonixnexusd.v1.MeshUserList
import gryonixnexusd.v1.PublishMeshNamesRequest
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of `AgentMeshOperationsTests` */
class AgentMeshOperationsTest {
    private fun nodes(vararg rows: gryonixnexusd.v1.MeshNode) = MeshNodeList(nodes = rows.toList())

    private fun names(vararg rows: Pair<String, String>) = MeshNameList(
        records = rows.map { (name, address) -> gryonixnexusd.v1.MeshName(name = name, address = address) },
    )

    private fun ops(transport: FakeAgentTransport) = AgentMeshOperations(AgentClient(transport))

    // --------------------------------------------------------------- Nodes

    @Test
    fun `a node carries its address user and online state`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Mesh/ListMeshNodes",
            nodes(
                gryonixnexusd.v1.MeshNode(
                    id = "1",
                    name = "b5",
                    addresses = listOf("100.64.0.1", "fd7a:115c:a1e0::1"),
                    user = "gryonixnexus",
                    online = true,
                    last_seen = 1_700_000_000,
                ),
            ),
        )

        val result = ops(transport).nodes()

        assertEquals(listOf("/gryonixnexusd.v1.Mesh/ListMeshNodes"), transport.paths)
        assertEquals(1, result.size)
        assertEquals("b5", result[0].name)
        assertEquals("100.64.0.1", result[0].addresses.first())
        assertEquals("gryonixnexus", result[0].user)
        assertTrue(result[0].isOnline)
        assertNotNull(result[0].lastSeen)
        assertEquals(Instant.ofEpochSecond(1_700_000_000), result[0].lastSeen)
    }

    @Test
    fun `an unknown last seen is null rather than nineteen seventy`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Mesh/ListMeshNodes",
            nodes(
                gryonixnexusd.v1.MeshNode(
                    id = "1",
                    name = "b5",
                    addresses = listOf("100.64.0.1"),
                    user = "u",
                    online = false,
                    last_seen = 0,
                ),
            ),
        )

        assertNull(ops(transport).nodes()[0].lastSeen)
    }

    // ---------------------------------------------------------- Auth keys

    @Test
    fun `a key with no expiry reads as no expiry`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Mesh/CreateMeshAuthKey", MeshAuthKey(key = "abc", reusable = true, expires_at = 0))

        val key = ops(transport).mintAuthKey(userID = "u", reusable = true, expirationHours = 0)

        assertEquals("abc", key.key)
        assertTrue(key.isReusable)
        assertNull(key.expiresAt)
    }

    // -------------------------------------------------- Publishing names

    @Test
    fun `publishing sends the names and reads back what the server wrote`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Mesh/PublishMeshNames",
            names("vault.example.com" to "100.64.0.1", "cloud.example.com" to "100.64.0.1"),
        )

        val records = ops(transport).publishNames(listOf("vault.example.com", "cloud.example.com"))

        assertEquals(listOf("/gryonixnexusd.v1.Mesh/PublishMeshNames"), transport.paths)
        val sent = PublishMeshNamesRequest.ADAPTER.decode(transport.calls.first().second)
        assertEquals(listOf("vault.example.com", "cloud.example.com"), sent.names)
        assertEquals("", sent.node_name)
        assertEquals(listOf("vault.example.com", "cloud.example.com"), records.map { it.name })
        assertEquals(setOf("100.64.0.1"), records.map { it.address }.toSet())
    }

    @Test
    fun `publishing nothing still calls the server`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Mesh/PublishMeshNames", names())

        assertTrue(ops(transport).publishNames(emptyList()).isEmpty())

        assertEquals(
            1,
            transport.paths.size,
            "an empty publish must still be sent — it is what clears the names",
        )
    }

    // ----------------------------------------------------------- The gate

    @Test
    fun `concurrent calls are serialized by a provided gate`() = runBlocking {
        val transport = GatedTransport(MeshNodeList())
        val ops = AgentMeshOperations(AgentClient(transport), gate = AgentChannelGate(limit = 1))

        (0 until 6).map { launch(Dispatchers.Default) { ops.nodes() } }.forEach { it.join() }

        assertEquals(1, transport.highest, "more than one call ran at once under a limit-1 gate")
    }

    @Test
    fun `with no gate calls genuinely overlap`() = runBlocking {
        val transport = GatedTransport(MeshNodeList())
        val ops = AgentMeshOperations(AgentClient(transport))

        (0 until 6).map { launch(Dispatchers.Default) { ops.nodes() } }.forEach { it.join() }

        assertTrue(
            transport.highest > 1,
            "calls did not overlap even without a gate — the harness is not sensitive",
        )
    }

    /** The publish verb goes under the gate too */
    @Test
    fun `publishing goes through the gate as well`() = runBlocking {
        val transport = GatedTransport(MeshNameList())
        val ops = AgentMeshOperations(AgentClient(transport), gate = AgentChannelGate(limit = 1))

        (0 until 6).map { launch(Dispatchers.Default) { ops.publishNames(listOf("a.example.com")) } }
            .forEach { it.join() }

        assertEquals(1, transport.highest, "publishing bypassed the gate")
    }

    @Test
    fun `listing users goes through the gate as well`() = runBlocking {
        val transport = GatedTransport(MeshUserList())
        val ops = AgentMeshOperations(AgentClient(transport), gate = AgentChannelGate(limit = 1))

        (0 until 6).map { launch(Dispatchers.Default) { ops.users() } }.forEach { it.join() }

        assertEquals(1, transport.highest, "listing users bypassed the gate")
    }

    // ----------------------------------------------------------- Refusals

    @Test
    fun `the server's own words survive as the error message`() = runTest {
        val transport = FakeAgentTransport()
        transport.refuse(
            "Mesh/PublishMeshNames",
            code = "failed_precondition",
            text = "this server does not run Headscale",
        )

        val error = runCatching {
            ops(transport).publishNames(listOf("vault.example.com"))
        }.exceptionOrNull()

        assertTrue(error?.message.orEmpty().contains("does not run Headscale"), "${error?.message}")
    }
}
