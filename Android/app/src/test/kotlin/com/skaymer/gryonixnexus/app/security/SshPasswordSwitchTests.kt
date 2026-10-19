package com.skaymer.gryonixnexus.app.security

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.agentclient.AgentTransport
import com.skaymer.gryonixnexus.agentcontrol.AgentSecurityOperations
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.AccessGrantCommand
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.ExecChunk
import com.skaymer.gryonixnexus.servercontrol.ExecResult
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import gryonixnexusd.v1.SshPasswordState
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SshPasswordSwitchTests {
    private val key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeFakeFakeFake gryonixnexus-app"

    private fun server() = Deployment(
        id = "S-1",
        name = "middle",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "admin"),
        services = emptySet(),
        usesAgent = true,
        usesPasswordAuth = true,
    )

    private class Scripted(private val stdout: String) : SSHCommandRunner {
        val asked = mutableListOf<Pair<String, SSHHostID>>()

        override suspend fun run(command: String, host: SSHHostID, timeout: Duration): ExecResult {
            asked += command to host
            return ExecResult(exitCode = 0, stdout = stdout, stderr = "")
        }

        override fun stream(command: String, host: SSHHostID, timeout: Duration): Flow<ExecChunk> =
            emptyFlow()

        override suspend fun fireAndForget(command: String, host: SSHHostID) = Unit
        override suspend fun disconnect() = Unit
    }

    /** The agent, answering one canned SSH-password state and nothing else */
    private class CannedAgent(private val state: SshPasswordState) : AgentTransport {
        override suspend fun unary(path: String, request: ByteArray): ByteArray =
            SshPasswordState.ADAPTER.encode(state)

        override fun serverStream(path: String, request: ByteArray): Flow<ByteArray> = emptyFlow()
    }

    private class Recorder {
        var updated: Deployment? = null
        var invalidated: String? = null
    }

    private fun model(
        grant: Scripted,
        probe: SSHCommandRunner,
        recorder: Recorder,
        agent: SshPasswordState = SshPasswordState(known = false),
    ) = SecurityViewModel(
        scope = scope!!,
        operations = { AgentSecurityOperations(AgentClient(CannedAgent(agent))) },
        publicKey = { key },
        runner = { grant },
        detached = { probe },
        onDeploymentUpdated = { recorder.updated = it },
        invalidate = { recorder.invalidated = it.id },
    )

    private var scope: kotlinx.coroutines.CoroutineScope? = null

    @Test
    fun `the record switches to key sign-in only after the key is proven`() = runTest {
        scope = this
        val deployment = server()
        val grant = Scripted("${AccessGrantCommand.MARKER} admin\n")
        val probe = Scripted("GRYONIXNEXUS_PING\n")
        val recorder = Recorder()

        model(grant, probe, recorder).grantAppKey(deployment)
        advanceUntilIdle()

        assertEquals(AccessGrantCommand.command(key), grant.asked.single().first)
        assertEquals(deployment.servicesHost, grant.asked.single().second)
        assertEquals(false, recorder.updated?.usesPasswordAuth)
        assertEquals(deployment.id, recorder.invalidated)
    }

    @Test
    fun `a key that does not sign in leaves the server on its password`() = runTest {
        scope = this
        val grant = Scripted("${AccessGrantCommand.MARKER} admin\n")
        val probe = Scripted("permission denied\n")
        val recorder = Recorder()
        val model = model(grant, probe, recorder)

        model.grantAppKey(server())
        advanceUntilIdle()

        assertNull(recorder.updated, "the server stopped using a password that works")
        assertNull(recorder.invalidated)
        assertNotNull(model.state.value.failure)
        assertFalse(model.state.value.busy)
    }

    @Test
    fun `a grant nobody confirmed commits nothing`() = runTest {
        scope = this
        val grant = Scripted("")
        val probe = Scripted("GRYONIXNEXUS_PING\n")
        val recorder = Recorder()
        val model = model(grant, probe, recorder)

        model.grantAppKey(server())
        advanceUntilIdle()

        assertNull(recorder.updated)
        assertNull(recorder.invalidated)
        assertNotNull(model.state.value.failure)
    }

    @Test
    fun `a key server keeps its session when the key is re-added`() = runTest {
        scope = this
        val grant = Scripted("${AccessGrantCommand.MARKER} gryonixnexus\n")
        val probe = Scripted("")
        val recorder = Recorder()

        model(grant, probe, recorder).grantAppKey(server().copy(usesPasswordAuth = false))
        advanceUntilIdle()

        assertNull(recorder.updated)
        assertNull(recorder.invalidated)
        assertEquals(1, grant.asked.size)
    }

    /** "Could not tell" draws no switch */
    @Test
    fun `an unknown reading offers nothing`() = runTest {
        scope = this
        val recorder = Recorder()
        val model = model(Scripted(""), Scripted(""), recorder,
                          agent = SshPasswordState(known = false, detail = "no systemd-run"))

        model.loadSshAccess(server())
        advanceUntilIdle()

        val access = model.state.value.sshAccess
        assertNotNull(access)
        assertFalse(access.isOpen)
        assertFalse(access.isClosed)
        assertFalse(access.canClose)
    }

    /** The guard, as the card sees it */
    @Test
    fun `no proven key means the close is not offered`() = runTest {
        scope = this
        val recorder = Recorder()
        val model = model(
            Scripted(""), Scripted(""), recorder,
            agent = SshPasswordState(
                password_login_open = true,
                known = true,
                app_key_present = false,
                sshd_present = true,
                login_user = "admin",
            ),
        )

        model.loadSshAccess(server())
        advanceUntilIdle()

        val access = model.state.value.sshAccess
        assertNotNull(access)
        assertTrue(access.isOpen)
        assertFalse(access.canClose)
    }

    @Test
    fun `a proven key makes the close offerable`() = runTest {
        scope = this
        val recorder = Recorder()
        val model = model(
            Scripted(""), Scripted(""), recorder,
            agent = SshPasswordState(
                password_login_open = true,
                known = true,
                app_key_present = true,
                sshd_present = true,
                login_user = "admin",
            ),
        )

        model.loadSshAccess(server())
        advanceUntilIdle()

        val access = model.state.value.sshAccess
        assertNotNull(access)
        assertTrue(access.canClose)
        assertEquals("admin", access.loginUser)
    }
}
