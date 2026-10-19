package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.servercontrol.ServiceControlRoute
import com.skaymer.gryonixnexus.servercontrol.DKIMRouting
import gryonixnexusd.v1.DkimRecord
import gryonixnexusd.v1.DkimRecordList
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of `AgentDkimOperationsTests` */
class AgentDkimOperationsTest {
    private fun records(vararg rows: Pair<String, String>) =
        DkimRecordList(records = rows.map { (name, value) -> DkimRecord(name = name, value_ = value) })

    private fun ops(transport: FakeAgentTransport) = AgentDkimOperations(AgentClient(transport))

    // ------------------------------------------------------------- Routing

    @Test
    fun `DKIM uses the agent only when there is a mail engine and an agent`() {
        assertEquals(
            ServiceControlRoute.AGENT,
            DKIMRouting.route(usesAgent = true, agentTransportAvailable = true, hasMailEngine = true),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            DKIMRouting.route(usesAgent = true, agentTransportAvailable = true, hasMailEngine = false),
        )
    }

    @Test
    fun `an agentless deployment keeps using the SSH wrapper`() {
        assertEquals(
            ServiceControlRoute.SSH,
            DKIMRouting.route(usesAgent = false, agentTransportAvailable = true, hasMailEngine = true),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            DKIMRouting.route(usesAgent = false, agentTransportAvailable = false, hasMailEngine = true),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            DKIMRouting.route(usesAgent = true, agentTransportAvailable = false, hasMailEngine = true),
        )
    }

    // ------------------------------------------------------------- The wire

    @Test
    fun `records come back with name and value`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Dkim/GetDkimRecords",
            records("dkim._domainkey.example.com" to "v=DKIM1; k=rsa; p=abc"),
        )

        val result = ops(transport).fetchRecords()

        assertEquals(listOf("/gryonixnexusd.v1.Dkim/GetDkimRecords"), transport.paths)
        assertEquals(1, result.size)
        assertEquals("dkim._domainkey.example.com", result[0].name)
        assertEquals("v=DKIM1; k=rsa; p=abc", result[0].value)
        assertEquals("TXT", result[0].type)
    }

    @Test
    fun `an engine with no key yet is an empty list not a failure`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Dkim/GetDkimRecords", records())
        assertTrue(ops(transport).fetchRecords().isEmpty())
    }

    @Test
    fun `multiple domains all come back in order`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Dkim/GetDkimRecords",
            records(
                "dkim._domainkey.a.example.com" to "v=DKIM1; p=aaa",
                "dkim._domainkey.b.example.com" to "v=DKIM1; p=bbb",
            ),
        )
        assertEquals(
            listOf("dkim._domainkey.a.example.com", "dkim._domainkey.b.example.com"),
            ops(transport).fetchRecords().map { it.name },
        )
    }

    // ------------------------------------------------------------ Refusals

    @Test
    fun `the engine's own words survive as the error message`() = runTest {
        // The same rule the mailbox seam follows: on this screen the server's
        val transport = FakeAgentTransport()
        transport.refuse(
            "Dkim/GetDkimRecords",
            code = "not_found",
            text = "no mail engine is installed on this host",
        )

        val error = runCatching { ops(transport).fetchRecords() }.exceptionOrNull()
        val text = error?.message.orEmpty()
        assertTrue(text.contains("no mail engine is installed on this host"), text)
    }

    @Test
    fun `an unreachable agent stays an agent error`() = runTest {
        val transport = FakeAgentTransport()
        transport.fail("Dkim/GetDkimRecords", AgentError.Rpc("unavailable", ""))

        val error = runCatching { ops(transport).fetchRecords() }.exceptionOrNull()
        assertTrue(error is AgentError.Rpc, "got ${error?.let { it::class.simpleName }}")
    }
}
