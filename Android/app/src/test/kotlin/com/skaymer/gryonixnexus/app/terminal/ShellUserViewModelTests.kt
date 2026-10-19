package com.skaymer.gryonixnexus.app.terminal

import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.ExecChunk
import com.skaymer.gryonixnexus.servercontrol.ExecResult
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.ShellUserCommand
import com.skaymer.gryonixnexus.catalog.Topology
import kotlin.test.assertEquals
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

/** Creating an account on the server, from the app's side */
class ShellUserViewModelTests {
    private fun server() = Deployment(
        id = "S-1",
        name = "shell",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.30", user = "root"),
    )

    private class Scripted(
        private val stdout: String = "",
        private val stderr: String = "",
    ) : SSHCommandRunner {
        var commands = mutableListOf<String>()
        override suspend fun run(command: String, host: SSHHostID, timeout: Duration): ExecResult {
            commands += command
            return ExecResult(exitCode = 0, stdout = stdout, stderr = stderr)
        }
        override fun stream(command: String, host: SSHHostID, timeout: Duration): Flow<ExecChunk> = emptyFlow()
        override suspend fun fireAndForget(command: String, host: SSHHostID) = Unit
        override suspend fun disconnect() = Unit
    }

    private fun model(scope: CoroutineScope, runner: SSHCommandRunner, key: String = "ssh-ed25519 AAAAKEY app") =
        ShellUserViewModel(scope = scope, publicKey = { key }, runner = { runner })

    @Test
    fun `the marker is what makes it a success`() = runTest(StandardTestDispatcher()) {
        val runner = Scripted(stdout = "${ShellUserCommand.MARKER} deploy")
        val model = model(CoroutineScope(coroutineContext), runner)

        model.create(server(), "deploy", sudo = false)
        runCurrent()

        assertEquals("deploy", model.state.value.created)
        assertNull(model.state.value.failure)
        assertTrue(model.state.value.busy.not())
    }

    @Test
    fun `without the marker the server's own words are reported`() = runTest(StandardTestDispatcher()) {
        val runner = Scripted(stderr = "sudo: a password is required")
        val model = model(CoroutineScope(coroutineContext), runner)

        model.create(server(), "deploy", sudo = false)
        runCurrent()

        assertNull(model.state.value.created)
        assertEquals("sudo: a password is required", model.state.value.failure)
    }

    /**
     * The guard is asked HERE and not only by the screen that disables its
     * button: a view model that trusts its caller is one that cannot be called
     * from a second screen later.
     */
    @Test
    fun `a name the guard refuses never reaches the server`() = runTest(StandardTestDispatcher()) {
        val runner = Scripted(stdout = ShellUserCommand.MARKER)
        val model = model(CoroutineScope(coroutineContext), runner)

        model.create(server(), "Root", sudo = false)
        runCurrent()

        assertTrue(runner.commands.isEmpty(), "a refused name still ran a command")
        assertNull(model.state.value.created)
        assertTrue(model.state.value.failure != null)
    }

    /** Without a key there is nothing to authorize, and the account would be unreachable. */
    @Test
    fun `no key for this server is refused before running`() = runTest(StandardTestDispatcher()) {
        val runner = Scripted(stdout = ShellUserCommand.MARKER)
        val model = model(CoroutineScope(coroutineContext), runner, key = "")

        model.create(server(), "deploy", sudo = false)
        runCurrent()

        assertTrue(runner.commands.isEmpty(), "it ran without a key to install")
        assertNull(model.state.value.created)
    }

    @Test
    fun `sudo travels into the command`() = runTest(StandardTestDispatcher()) {
        val runner = Scripted(stdout = ShellUserCommand.MARKER)
        val model = model(CoroutineScope(coroutineContext), runner)

        model.create(server(), "deploy", sudo = true)
        runCurrent()

        assertTrue(
            runner.commands.single().contains("NOPASSWD:ALL"),
            "the sudo switch did not reach the script: ${runner.commands.single()}",
        )
    }
}
