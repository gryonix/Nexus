package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.servercontrol.MailboxRouting
import com.skaymer.gryonixnexus.servercontrol.ServiceControlRoute
import gryonixnexusd.v1.CreateMailboxRequest
import gryonixnexusd.v1.Mailbox
import gryonixnexusd.v1.MailboxList
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of `AgentMailboxOperationsTests` */
class AgentMailboxOperationsTest {
    private fun listing(vararg rows: Pair<String, String>) = MailboxList(
        mailboxes = rows.map { (address, detail) ->
            Mailbox(address = address, detail = detail, manageable = true)
        },
    )

    private fun ops(transport: FakeAgentTransport, engineInstalled: Boolean = true) =
        AgentMailboxOperations(AgentClient(transport), engineInstalled = engineInstalled)

    // ------------------------------------------------------------- Routing

    @Test
    fun `mailboxes use the agent only when there is an engine and an agent`() {
        assertEquals(
            ServiceControlRoute.AGENT,
            MailboxRouting.route(usesAgent = true, agentTransportAvailable = true, hasEngine = true),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            MailboxRouting.route(usesAgent = true, agentTransportAvailable = true, hasEngine = false),
        )
    }

    @Test
    fun `an agentless deployment keeps using the wrapper over SSH`() {
        assertEquals(
            ServiceControlRoute.SSH,
            MailboxRouting.route(usesAgent = false, agentTransportAvailable = true, hasEngine = true),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            MailboxRouting.route(usesAgent = false, agentTransportAvailable = false, hasEngine = true),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            MailboxRouting.route(usesAgent = true, agentTransportAvailable = false, hasEngine = true),
        )
    }

    // ------------------------------------------------------------- The wire

    @Test
    fun `listing rows become mailboxes with their detail`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Mail/ListMailboxes",
            listing(
                "admin@example.com" to "( 6.0K / ~ ) [0%]",
                "fresh@example.com" to "(  /  ) [%]",
            ),
        )

        val mailboxes = ops(transport).list()

        assertEquals(listOf("/gryonixnexusd.v1.Mail/ListMailboxes"), transport.paths)
        assertEquals(listOf("admin@example.com", "fresh@example.com"), mailboxes.map { it.address })
        assertEquals("( 6.0K / ~ ) [0%]", mailboxes[0].detail)
        assertEquals("(  /  ) [%]", mailboxes[1].detail)
    }

    @Test
    fun `an empty detail becomes null not an empty string`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Mail/ListMailboxes", listing("only@example.com" to ""))
        assertNull(ops(transport).list().first().detail)
    }

    @Test
    fun `an empty listing is no mailboxes not a failure`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Mail/ListMailboxes", listing())
        assertTrue(ops(transport).list().isEmpty())
    }

    @Test
    fun `the password travels in the request and the address is sent verbatim`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Mail/CreateMailbox", listing("new@example.com" to ""))

        ops(transport).add("new@example.com", "s3cr3t-pass")

        assertEquals(listOf("/gryonixnexusd.v1.Mail/CreateMailbox"), transport.paths)
        val sent = CreateMailboxRequest.ADAPTER.decode(transport.calls.first().second)
        assertEquals("new@example.com", sent.address)
        assertEquals("s3cr3t-pass", sent.password)
    }

    @Test
    fun `delete and password use their own typed routes`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Mail/DeleteMailbox", listing())
        transport.reply("Mail/SetMailboxPassword", listing())

        ops(transport).delete("old@example.com")
        ops(transport).setPassword("old@example.com", "pw")

        assertEquals(
            listOf("/gryonixnexusd.v1.Mail/DeleteMailbox", "/gryonixnexusd.v1.Mail/SetMailboxPassword"),
            transport.paths,
        )
    }

    // ------------------------------------------------------------ Refusals

    /** The same rule both routes enforce */
    @Test
    fun `a bad address is refused before anything is sent`() = runTest {
        val transport = FakeAgentTransport()
        val bad = listOf("", "-admin@example.com", "admin", "a@b@c", "admin@example.com; rm -rf /")

        for (address in bad) {
            val error = runCatching { ops(transport).add(address, "pw") }.exceptionOrNull()
            assertTrue(error != null, "$address should have been refused")
        }

        assertTrue(transport.paths.isEmpty(), "not one of those reached the wire")
    }

    @Test
    fun `an empty password is refused before anything is sent`() = runTest {
        val transport = FakeAgentTransport()
        val error = runCatching { ops(transport).add("a@b.com", "") }.exceptionOrNull()
        assertTrue(error != null, "an empty password should have been refused")
        assertTrue(transport.paths.isEmpty())
    }

    @Test
    fun `without the engine every call refuses and nothing is sent`() = runTest {
        val transport = FakeAgentTransport()
        val error = runCatching { ops(transport, engineInstalled = false).list() }.exceptionOrNull()
        assertTrue(error != null, "a deployment without the engine has nothing to list")
        assertTrue(transport.paths.isEmpty())
    }

    @Test
    fun `the engine's own words survive as the error message`() = runTest {
        // On this screen the engine's message is the ONLY explanation a user
        val transport = FakeAgentTransport()
        transport.refuse(
            "Mail/DeleteMailbox",
            code = "failed_precondition",
            text = "delmailuser: Mailbox data directory does not exist",
        )

        val error = runCatching { ops(transport).delete("gone@example.com") }.exceptionOrNull()
        val text = error?.message.orEmpty()
        assertTrue(text.contains("Mailbox data directory does not exist"), text)
    }
}
