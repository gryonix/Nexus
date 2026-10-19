package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.NodeCapability
import com.skaymer.gryonixnexus.servercontrol.ExecChunk
import com.skaymer.gryonixnexus.servercontrol.ExecResult
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import java.io.IOException
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

/** Adding a machine to a server that already exists */
class AddMachineViewModelTests {
    private fun server() = Deployment(
        id = "S-1",
        name = "middle",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
        services = setOf(ServiceID.NEXTCLOUD),
    )

    private class Scripted(
        val answer: String = AddMachineViewModel.MARKER,
        val fail: Boolean = false,
    ) : SSHCommandRunner {
        var hungUp = false
        var askedOn: SSHHostID? = null
        var reachedHosts = mutableListOf<String>()

        override suspend fun run(command: String, host: SSHHostID, timeout: Duration): ExecResult {
            askedOn = host
            if (fail) throw IOException("no route to host")
            return ExecResult(exitCode = 0, stdout = answer, stderr = "")
        }

        override fun stream(command: String, host: SSHHostID, timeout: Duration): Flow<ExecChunk> =
            emptyFlow()

        override suspend fun fireAndForget(command: String, host: SSHHostID) = Unit

        override suspend fun disconnect() {
            hungUp = true
        }
    }

    private fun model(
        scope: CoroutineScope,
        runner: Scripted,
        saved: MutableList<Deployment> = mutableListOf(),
        seen: MutableList<Deployment> = mutableListOf(),
    ) = AddMachineViewModel(
        scope = scope,
        trialRunners = { trial -> seen += trial; runner },
        persist = { saved += it },
    )

    @Test
    fun `the candidate is a worker and nothing more`() {
        val node = AddMachineViewModel.candidate("10.0.0.9", "2222", "admin", " lab ", null)
        assertEquals(setOf(NodeCapability.WORKER), node.capabilities)
        assertFalse(node.isIngress)
        assertEquals(2222, node.endpoint.port)
        assertEquals("lab", node.name)
    }

    @Test
    fun `a port nobody typed is the standard one`() {
        assertEquals(22, AddMachineViewModel.candidate("10.0.0.9", "", "admin", "", null).endpoint.port)
        assertEquals(22, AddMachineViewModel.candidate("10.0.0.9", "nope", "admin", "", null).endpoint.port)
    }

    @Test
    fun `the check dials the deployment as it WOULD be`() = runTest(StandardTestDispatcher()) {
        val runner = Scripted()
        val seen = mutableListOf<Deployment>()
        val machines = model(this, runner, seen = seen)
        val node = AddMachineViewModel.candidate("10.0.0.9", "22", "admin", "", null)
        machines.check(server(), node)
        runCurrent()

        assertTrue(seen.single().nodes.any { it.id == node.id })
        assertEquals(node.sshHost, runner.askedOn)
        assertTrue(runner.hungUp)
        assertEquals(node, machines.state.value.proved)
    }

    @Test
    fun `a machine that says something else is not proved`() = runTest(StandardTestDispatcher()) {
        val machines = model(this, Scripted(answer = "Welcome to Ubuntu"))
        machines.check(server(), AddMachineViewModel.candidate("10.0.0.9", "22", "admin", "", null))
        runCurrent()

        assertNull(machines.state.value.proved)
        assertNotNull(machines.state.value.errorMessage)
    }

    @Test
    fun `a machine that cannot be reached is not written down`() = runTest(StandardTestDispatcher()) {
        val runner = Scripted(fail = true)
        val saved = mutableListOf<Deployment>()
        val machines = model(this, runner, saved = saved)
        machines.check(server(), AddMachineViewModel.candidate("10.0.0.9", "22", "admin", "", null))
        runCurrent()

        assertEquals("no route to host", machines.state.value.errorMessage)
        assertFalse(machines.add(server()))
        assertTrue(saved.isEmpty())
        assertTrue(runner.hungUp)
    }

    @Test
    fun `what is stored is what answered`() = runTest(StandardTestDispatcher()) {
        val saved = mutableListOf<Deployment>()
        val machines = model(this, Scripted(), saved = saved)
        val node = AddMachineViewModel.candidate("10.0.0.9", "22", "admin", "lab", null)
        machines.check(server(), node)
        runCurrent()
        assertTrue(machines.add(server()))

        assertEquals(node, saved.single().nodes.first { it.id == node.id })
    }

    @Test
    fun `a machine the rules refuse never gets dialled`() = runTest(StandardTestDispatcher()) {
        val runner = Scripted()
        val seen = mutableListOf<Deployment>()
        val machines = model(this, runner, seen = seen)
        machines.check(
            server(),
            AddMachineViewModel.candidate("10.0.0.9", "22", "admin", "", routedThrough = "nobody"),
        )
        runCurrent()

        assertTrue(seen.isEmpty())
        assertNull(machines.state.value.proved)
        assertNotNull(machines.state.value.errorMessage)
    }

    @Test
    fun `nothing is dialled until there is something to dial`() {
        assertFalse(AddMachineViewModel.canCheck("", "admin"))
        assertFalse(AddMachineViewModel.canCheck("10.0.0.9", "  "))
        assertTrue(AddMachineViewModel.canCheck("10.0.0.9", "admin"))
    }

    @Test
    fun `a password-signed server needs THIS machine's own password`() {
        // The accounts are ordinary accounts on ordinary machines and nothing
        // makes their passwords the same; without one the dial falls through to
        // a key nobody put in this machine's authorized_keys. Found on a phone:
        assertFalse(
            AddMachineViewModel.canCheck("10.0.0.9", "admin", password = "", needsPassword = true)
        )
        assertTrue(
            AddMachineViewModel.canCheck("10.0.0.9", "admin", password = "hunter2", needsPassword = true)
        )
        assertTrue(
            AddMachineViewModel.canCheck("10.0.0.9", "admin", password = "", needsPassword = false)
        )
    }

    @Test
    fun `the password is kept before the machine is dialled, and only then`() =
        runTest(StandardTestDispatcher()) {
            val kept = mutableListOf<Pair<String, String>>()
            val model = AddMachineViewModel(
                scope = this,
                trialRunners = { Scripted() },
                rememberPassword = { _, node, password -> kept += node.id to password },
            )
            val keyed = server()
            val passworded = keyed.copy(usesPasswordAuth = true)
            val node = AddMachineViewModel.candidate("10.0.0.9", "22", "admin", "", null)

            model.check(keyed, node, "typed-anyway")
            runCurrent()
            assertTrue(kept.isEmpty())

            model.reset()
            model.check(passworded, node, "the-lab-password")
            runCurrent()
            assertEquals(listOf(node.id to "the-lab-password"), kept)
        }
}
