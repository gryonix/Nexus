package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.CommandCatalog
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.ExecChunk
import com.skaymer.gryonixnexus.servercontrol.ExecResult
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.PingResult
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue
import kotlin.time.Duration
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class RelayStatusViewModelTests {
    private fun pair() = Deployment(
        id = "S-2",
        name = "pair",
        topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.41", user = "root"),
        homeWGAddress = "10.8.0.2",
    )

    private fun single() = Deployment(
        id = "S-1",
        name = "middle",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
    )

    private class Recording(
        private val vpsOut: String = probeReply(forwarding = FORWARDING_ON, self = 1, tunnel = 1),
        private val homeOut: String = FORWARDING_ON,
        private val refuse: Set<SSHHostID> = emptySet(),
    ) : SSHCommandRunner {
        val ran = mutableListOf<Pair<String, SSHHostID>>()

        override suspend fun run(command: String, host: SSHHostID, timeout: Duration): ExecResult {
            ran += command to host
            if (host in refuse) return ExecResult(exitCode = 255, stdout = "", stderr = "no route to host")
            return ExecResult(exitCode = 0, stdout = if (host == SSHHostID.HOME) homeOut else vpsOut, stderr = "")
        }

        override fun stream(command: String, host: SSHHostID, timeout: Duration): Flow<ExecChunk> = emptyFlow()
        override suspend fun fireAndForget(command: String, host: SSHHostID) = Unit
        override suspend fun disconnect() = Unit
    }

    private companion object {
        const val FORWARDING_ON = "net.ipv4.ip_forward = 1"

        fun probeReply(forwarding: String, self: Int, tunnel: Int): String = listOf(
            forwarding,
            "1 packets transmitted, $self received, 0% packet loss",
            "1 packets transmitted, $tunnel received, 0% packet loss",
        ).joinToString("\n${CommandCatalog.GENERAL_PROBE_SEPARATOR}\n")
    }

    /** Only a relay pair has a relay path */
    @Test
    fun `the rows are offered to a pair and to nothing else`() {
        assertTrue(RelayStatusViewModel.offered(pair()))
        assertFalse(RelayStatusViewModel.offered(single()))
    }

    @Test
    fun `a single host is never probed`() = runTest {
        val runner = Recording()
        val model = RelayStatusViewModel(this, { runner })
        model.refresh(single())
        runCurrent()
        assertEquals(emptyList(), runner.ran)
    }

    @Test
    fun `the relay is asked once and the home half separately`() = runTest {
        val runner = Recording()
        val model = RelayStatusViewModel(this, { runner })
        model.refresh(pair())
        runCurrent()

        assertEquals(listOf(SSHHostID.VPS, SSHHostID.HOME), runner.ran.map { it.second })
        val state = model.state.value
        assertEquals(RelayRead.Loaded(true), state.forwardingVPS)
        assertEquals(RelayRead.Loaded(true), state.forwardingHome)
        assertEquals(PingResult(1, 1), assertIs<RelayRead.Loaded<PingResult>>(state.selfPing).value)
        assertEquals(PingResult(1, 1), assertIs<RelayRead.Loaded<PingResult>>(state.tunnelPing).value)
    }

    @Test
    fun `the home half is still asked when the relay refuses`() = runTest {
        val runner = Recording(refuse = setOf(SSHHostID.VPS))
        val model = RelayStatusViewModel(this, { runner })
        model.refresh(pair())
        runCurrent()

        val state = model.state.value
        assertIs<RelayRead.Failed>(state.forwardingVPS)
        assertIs<RelayRead.Failed>(state.selfPing)
        assertEquals(RelayRead.Loaded(true), state.forwardingHome)
        assertTrue(runner.ran.any { it.second == SSHHostID.HOME })
    }

    @Test
    fun `forwarding is on only when both halves forward`() {
        val both = RelayStatusState(
            forwardingVPS = RelayRead.Loaded(true),
            forwardingHome = RelayRead.Loaded(true),
        )
        assertEquals(RelayRead.Loaded(true), both.forwarding)

        val half = RelayStatusState(
            forwardingVPS = RelayRead.Loaded(true),
            forwardingHome = RelayRead.Loaded(false),
        )
        assertEquals(RelayRead.Loaded(false), half.forwarding)
    }

    @Test
    fun `a failure on either half is what the merged row says`() {
        val relayDown = RelayStatusState(
            forwardingVPS = RelayRead.Failed("no route to host"),
            forwardingHome = RelayRead.Loaded(true),
        )
        assertEquals(RelayRead.Failed("no route to host"), relayDown.forwarding)

        val homeDown = RelayStatusState(
            forwardingVPS = RelayRead.Loaded(true),
            forwardingHome = RelayRead.Failed("timed out"),
        )
        assertEquals(RelayRead.Failed("timed out"), homeDown.forwarding)

        assertEquals(
            RelayRead.Loading,
            RelayStatusState(forwardingVPS = RelayRead.Loading).forwarding,
        )
        assertEquals(RelayRead.Idle, RelayStatusState().forwarding)
    }
}
