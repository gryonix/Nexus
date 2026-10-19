package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.servercontrol.ServerControlError
import gryonixnexusd.v1.DynamicDNSState
import gryonixnexusd.v1.SetDynamicDNSRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of `AgentDynamicDNSOperationsTests` */
class AgentDynamicDNSOperationsTest {
    private fun state(
        enabled: Boolean,
        zone: String = "",
        names: List<String> = emptyList(),
        hasToken: Boolean = false,
        recent: List<String> = emptyList(),
    ) = DynamicDNSState(
        enabled = enabled,
        zone = zone,
        names = names,
        has_token = hasToken,
        recent = recent,
    )

    private fun ops(transport: FakeAgentTransport) = AgentDynamicDNSOperations(AgentClient(transport))

    private fun FakeAgentTransport.sent(): SetDynamicDNSRequest =
        SetDynamicDNSRequest.ADAPTER.decode(calls.last().second)

    @Test
    fun `state comes back with the recent runs the host recorded`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Dns/GetDynamicDNS",
            state(
                enabled = true,
                zone = "example.com",
                names = listOf("home.example.com"),
                hasToken = true,
                recent = listOf(
                    "2026-08-15T17:18:57Z GRYONIXNEXUS_DDNS_UPDATED home.example.com 1.2.3.4 -> 5.6.7.8",
                ),
            ),
        )

        val answer = ops(transport).state()

        assertEquals(listOf("/gryonixnexusd.v1.Dns/GetDynamicDNS"), transport.paths)
        assertTrue(answer.enabled)
        assertEquals(listOf("home.example.com"), answer.names)
        assertTrue(answer.has_token)
        assertEquals(1, answer.recent.size)
    }

    /** The credential goes UP and is never read back down */
    @Test
    fun `the answer carries whether a token is held and never the token itself`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Dns/GetDynamicDNS",
            state(enabled = true, zone = "example.com", names = listOf("home.example.com"), hasToken = true),
        )

        val answer = ops(transport).state()

        assertTrue(answer.has_token)
        val fields = DynamicDNSState::class.java.declaredFields.map { it.name }
        assertFalse("token" in fields, "the state must not carry a token field: $fields")
        assertTrue("token" in SetDynamicDNSRequest::class.java.declaredFields.map { it.name })
    }

    @Test
    fun `an empty token is sent when the host already holds one`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Dns/SetDynamicDNS",
            state(
                enabled = true,
                zone = "example.com",
                names = listOf("a.example.com", "b.example.com"),
                hasToken = true,
            ),
        )

        ops(transport).enable("example.com", listOf("a.example.com", "b.example.com"))

        assertEquals(listOf("/gryonixnexusd.v1.Dns/SetDynamicDNS"), transport.paths)
        assertEquals("example.com", transport.sent().zone)
        assertEquals(listOf("a.example.com", "b.example.com"), transport.sent().names)
        assertEquals("", transport.sent().token, "an empty token means keep the stored one")
    }

    @Test
    fun `disable sends no names`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Dns/SetDynamicDNS", state(enabled = false))

        val answer = ops(transport).disable()

        assertFalse(answer.enabled)
        assertTrue(transport.sent().names.isEmpty())
        assertEquals("", transport.sent().zone)
    }

    @Test
    fun `a refusal arrives as a command failure carrying the reason`() = runTest {
        val transport = FakeAgentTransport()
        transport.refuse(
            "Dns/SetDynamicDNS",
            code = "invalid_argument",
            text = "a b.example.com is not a hostname",
        )

        val error = runCatching {
            ops(transport).enable("example.com", listOf("a b.example.com"), token = "t")
        }.exceptionOrNull()

        assertTrue(error is ServerControlError.CommandFailed, "got $error")
        assertTrue(error.stderr.contains("is not a hostname"), error.stderr)
    }

    // ---------------------------------------------------------- The gate

    @Test
    fun `concurrent calls are serialized by a provided gate`() = runBlocking {
        val transport = GatedTransport(DynamicDNSState())
        val ops = AgentDynamicDNSOperations(AgentClient(transport), gate = AgentChannelGate(limit = 1))

        (0 until 6).map { launch(Dispatchers.Default) { ops.state() } }.forEach { it.join() }

        assertEquals(1, transport.highest, "more than one call ran at once under a limit-1 gate")
    }

    @Test
    fun `with no gate calls genuinely overlap`() = runBlocking {
        val transport = GatedTransport(DynamicDNSState())
        val ops = AgentDynamicDNSOperations(AgentClient(transport))

        (0 until 6).map { launch(Dispatchers.Default) { ops.state() } }.forEach { it.join() }

        assertTrue(
            transport.highest > 1,
            "calls did not overlap even without a gate — the harness is not sensitive",
        )
    }
}
