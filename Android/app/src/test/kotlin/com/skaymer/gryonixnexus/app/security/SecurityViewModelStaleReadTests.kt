package com.skaymer.gryonixnexus.app.security

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.agentclient.AgentTransport
import com.skaymer.gryonixnexus.agentcontrol.AgentSecurityOperations
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import gryonixnexusd.v1.SecurityStatus
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SecurityViewModelStaleReadTests {
    private fun server(id: String, host: String) = Deployment(
        id = id,
        name = id,
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = host, user = "root"),
        services = emptySet(),
        usesAgent = true,
    )

    private class CannedTransport(private val version: String) : AgentTransport {
        override suspend fun unary(path: String, request: ByteArray): ByteArray =
            SecurityStatus.ADAPTER.encode(SecurityStatus(present = true, engine_version = version))

        override fun serverStream(path: String, request: ByteArray): Flow<ByteArray> = emptyFlow()
    }

    @Test
    fun `a read that outlives its server does not land on the next one`() = runTest {
        val slow = server("S-1", "203.0.113.40")
        val quick = server("S-2", "203.0.113.41")
        val gates = mapOf(slow.id to CompletableDeferred<Unit>(), quick.id to CompletableDeferred())
        val versions = mapOf(slow.id to "v1.0.0-first", quick.id to "v1.8.0-second")

        val model = SecurityViewModel(
            scope = this,
            operations = { deployment ->
                gates.getValue(deployment.id).await()
                AgentSecurityOperations(AgentClient(CannedTransport(versions.getValue(deployment.id))))
            },
        )

        model.load(slow)
        model.reset()
        model.load(quick)

        gates.getValue(quick.id).complete(Unit)
        advanceUntilIdle()
        assertEquals(
            "v1.8.0-second",
            model.state.value.status?.engineVersion,
            "the card should be showing the server it is open on",
        )

        gates.getValue(slow.id).complete(Unit)
        advanceUntilIdle()
        assertEquals(
            "v1.8.0-second",
            model.state.value.status?.engineVersion,
            "the previous server's answer landed on this server's card",
        )
        assertTrue(model.state.value.hasAnswered)
    }

    @Test
    fun `leaving the card drops the read it started`() = runTest {
        val open = server("S-1", "203.0.113.40")
        val gate = CompletableDeferred<Unit>()

        val model = SecurityViewModel(
            scope = this,
            operations = {
                gate.await()
                AgentSecurityOperations(AgentClient(CannedTransport("v1.8.0")))
            },
        )

        model.load(open)
        model.reset()

        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(
            SecurityScreenState(),
            model.state.value,
            "a card that was left behind answered anyway",
        )
    }
}
