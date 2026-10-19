package com.skaymer.gryonixnexus.app.agent

import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AgentPresenceTests {
    private fun server(usesAgent: Boolean = false) = Deployment(
        id = "S-1",
        name = "middle",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
        usesAgent = usesAgent,
    )

    @Test
    fun `a version is what the host answered`() {
        assertEquals(
            AgentPresence.Answer.Installed("0.0.101"),
            AgentPresence.answered("0.0.101"),
        )
    }

    @Test
    fun `an empty version still means the agent is there`() {
        assertEquals(AgentPresence.Answer.InstalledUnknownVersion, AgentPresence.answered(""))
        assertEquals(AgentPresence.Answer.InstalledUnknownVersion, AgentPresence.answered("   "))
    }

    @Test
    fun `a refusal carries the reason the host gave`() {
        val answer = AgentPresence.refused(IOException("the agent bridge did not start: sudo: a password is required"))
        assertEquals(
            AgentPresence.Answer.Unreachable(
                "the agent bridge did not start: sudo: a password is required"
            ),
            answer,
        )
    }

    @Test
    fun `an error with no message still says something`() {
        val answer = AgentPresence.refused(IOException()) as AgentPresence.Answer.Unreachable
        assertTrue(answer.reason.isNotBlank(), "an unreachable host with no words is a blank line")
    }

    @Test
    fun `a host that answers repairs a record that said it had no agent`() {
        val repaired = AgentPresence.repaired(server(usesAgent = false), AgentPresence.answered("0.0.101"))
        assertEquals(true, repaired?.usesAgent)
    }

    @Test
    fun `a host answering without a version repairs the record too`() {
        val repaired = AgentPresence.repaired(server(usesAgent = false), AgentPresence.answered(""))
        assertEquals(true, repaired?.usesAgent)
    }

    @Test
    fun `a record that is already right is not rewritten`() {
        assertNull(
            AgentPresence.repaired(server(usesAgent = true), AgentPresence.answered("0.0.101")),
            "a fleet write nobody asked for, on every check of every agent server",
        )
    }

    @Test
    fun `a host that cannot be reached does not clear the record`() {
        assertNull(
            AgentPresence.repaired(server(usesAgent = true), AgentPresence.refused(IOException("no route"))),
            "one bad connection must not erase a fact that took an install to establish",
        )
        assertNull(
            AgentPresence.repaired(server(usesAgent = false), AgentPresence.refused(IOException("no route"))),
        )
    }

    private fun viewModel(
        scope: CoroutineScope,
        version: suspend (Deployment) -> String,
        onAgentFound: suspend (Deployment) -> Unit = {},
    ) = AgentInstallViewModel(
        scope = scope,
        runners = { error("the check does not open a runner of its own") },
        browsers = { error("the check does not browse files") },
        sources = { ByteArray(0) },
        version = version,
        onAgentFound = onAgentFound,
    )

    @Test
    fun `checking a server the app thought had no agent records that it has`() = runTest {
        val written = mutableListOf<Deployment>()
        val model = viewModel(
            scope = CoroutineScope(StandardTestDispatcher(testScheduler)),
            version = { "0.0.101" },
            onAgentFound = { written += it },
        )
        model.check(server(usesAgent = false))
        testScheduler.advanceUntilIdle()

        assertEquals(AgentPresence.Answer.Installed("0.0.101"), model.check.value.answer)
        assertEquals(listOf(true), written.map { it.usesAgent })
    }

    @Test
    fun `a check that fails says why and writes nothing`() = runTest {
        val written = mutableListOf<Deployment>()
        val model = viewModel(
            scope = CoroutineScope(StandardTestDispatcher(testScheduler)),
            version = { throw IOException("the agent bridge did not start: Connection refused") },
            onAgentFound = { written += it },
        )
        model.check(server(usesAgent = true))
        testScheduler.advanceUntilIdle()

        assertEquals(
            AgentPresence.Answer.Unreachable("the agent bridge did not start: Connection refused"),
            model.check.value.answer,
        )
        assertTrue(written.isEmpty(), "a failed check must not touch the fleet")
    }
}
