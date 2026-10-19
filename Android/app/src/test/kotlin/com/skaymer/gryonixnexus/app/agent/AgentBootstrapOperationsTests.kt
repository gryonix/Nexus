package com.skaymer.gryonixnexus.app.agent

import com.skaymer.gryonixnexus.recipe.AgentBootstrapSections
import com.skaymer.gryonixnexus.servercontrol.DetachedAgentBuild
import com.skaymer.gryonixnexus.servercontrol.ExecChunk
import com.skaymer.gryonixnexus.servercontrol.ExecResult
import com.skaymer.gryonixnexus.servercontrol.RemoteFileBrowser
import com.skaymer.gryonixnexus.servercontrol.RemoteFileEntry
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.ServerControlError
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import kotlin.time.Duration

class AgentBootstrapOperationsTests {
    /** A machine that answers by script */
    private open class Machine(
        val home: String = "/home/gryonix",
        val wrapperRuns: MutableList<String?> = mutableListOf(),
        /** What a FAILING run prints before it dies, in order */
        val refusals: MutableList<String> = mutableListOf(),
    ) : SSHCommandRunner, RemoteFileBrowser {
        val uploads = mutableListOf<Pair<String, ByteArray>>()
        val commands = mutableListOf<String>()
        var installExit = 0
        private var run = 0

        override suspend fun homeDirectory(host: SSHHostID) = home
        override suspend fun listDirectory(path: String, host: SSHHostID) =
            emptyList<RemoteFileEntry>()
        override suspend fun downloadFile(path: String, host: SSHHostID, maxBytes: Long) =
            ByteArray(0)
        open override suspend fun uploadFile(data: ByteArray, path: String, host: SSHHostID) {
            uploads += path to data
        }
        override suspend fun deleteFile(entry: RemoteFileEntry, host: SSHHostID) = Unit

        override suspend fun run(command: String, host: SSHHostID, timeout: Duration): ExecResult {
            commands += command
            return ExecResult(exitCode = installExit, stdout = "", stderr = "")
        }

        override fun stream(command: String, host: SSHHostID, timeout: Duration): Flow<ExecChunk> {
            commands += command
            val index = run++
            val scripted = wrapperRuns.getOrNull(index)
            val refusal = refusals.removeFirstOrNull()
            val log = if (scripted == null) (refusal?.let { "$it\n" }.orEmpty()) + "${DetachedAgentBuild.EXIT_MARKER}1\n"
            else "$scripted\n${DetachedAgentBuild.EXIT_MARKER}0\n"
            return flow { emit(ExecChunk.Stdout(log)) }
        }

        override suspend fun fireAndForget(command: String, host: SSHHostID) = Unit
        override suspend fun disconnect() = Unit
    }

    private val sources = AgentBootstrapOperations.Sources { "TARBALL".toByteArray() }
    private val quiet = AgentBootstrapOperations.Reporter { }

    private suspend fun install(machine: Machine, onPhase: AgentBootstrapOperations.Reporter = quiet) =
        AgentBootstrapOperations.install(
            runner = machine,
            files = machine,
            host = SSHHostID.VPS,
            sources = sources,
            onPhase = onPhase,
            onOutput = quiet,
        )

    @Test
    fun `the archive goes to the login user's own home`() = runTest {
        // Not /root: the app connects as the deployment's CONTROL user, whose
        val machine = Machine(wrapperRuns = mutableListOf("built"))
        install(machine)
        assertEquals(
            "/home/gryonix/${AgentBootstrapSections.ARCHIVE_NAME}",
            machine.uploads.single().first,
        )
    }

    @Test
    fun `a missing wrapper is written and the build retried`() = runTest {
        val machine = Machine(
            wrapperRuns = mutableListOf(
                null,     // refuses, with the transcript below
                "built",  // and succeeds once the wrapper exists
            ),
            refusals = mutableListOf(
                "sudo: ${AgentBootstrapSections.SCRIPT_PATH}: command not found",
            ),
        )
        val phases = mutableListOf<String>()
        install(machine, onPhase = { phases += it })

        val staged = "/home/gryonix/.gryonixnexus-agent-bootstrap.sh"
        assertTrue(machine.uploads.any { it.first == staged }, "the wrapper must be staged")
        assertTrue(
            machine.commands.any {
                it.startsWith("sudo -n install -o root -g root -m 700") &&
                    it.contains(staged) && it.contains(AgentBootstrapSections.SCRIPT_PATH)
            },
            "the staged wrapper must be installed root-owned: ${machine.commands}",
        )
        assertTrue(machine.commands.any { it.startsWith("rm -f") && it.contains(staged) })
        val written = machine.uploads.first { it.first == staged }.second.decodeToString()
        assertTrue(
            written.contains("/home/gryonix/${AgentBootstrapSections.ARCHIVE_NAME}"),
            "the wrapper must read the archive this session uploaded",
        )
        assertEquals(
            listOf(
                AgentBootstrapOperations.SENDING,
                AgentBootstrapOperations.BUILDING,
                AgentBootstrapOperations.PREPARING,
                AgentBootstrapOperations.BUILDING,
            ),
            phases,
        )
    }

    @Test
    fun `an archive the wrapper cannot see is re-uploaded where it looks`() = runTest {
        val machine = Machine(
            wrapperRuns = mutableListOf(null, "built"),
            refusals = mutableListOf(
                "no agent sources uploaded (/root/${AgentBootstrapSections.ARCHIVE_NAME})",
            ),
        )
        val phases = mutableListOf<String>()
        install(machine, onPhase = { phases += it })

        assertEquals(
            listOf(
                "/home/gryonix/${AgentBootstrapSections.ARCHIVE_NAME}",
                "/root/${AgentBootstrapSections.ARCHIVE_NAME}",
            ),
            machine.uploads.map { it.first },
            "the second upload goes where the wrapper said it looks",
        )
        assertTrue(phases.contains(AgentBootstrapOperations.RELOCATING))
    }

    @Test
    fun `a relocation this account cannot write says which path`() = runTest {
        val machine = object : Machine(
            wrapperRuns = mutableListOf(null),
            refusals = mutableListOf(
                "no agent sources uploaded (/root/${AgentBootstrapSections.ARCHIVE_NAME})",
            ),
        ) {
            override suspend fun uploadFile(data: ByteArray, path: String, host: SSHHostID) {
                if (path.startsWith("/root/")) throw IllegalStateException("status 3")
                super.uploadFile(data, path, host)
            }
        }
        val failure = assertFailsWith<ServerControlError.NotConfigured> { install(machine) }
        assertTrue(
            failure.detail.contains("/root/${AgentBootstrapSections.ARCHIVE_NAME}"),
            "the refusal must name the path the server looks in: ${failure.detail}",
        )
    }

    @Test
    fun `the path the wrapper wanted is read out of its own refusal`() {
        val said = "no agent sources uploaded (/root/gryonixnexus-agent-src.tar.gz)"
        assertEquals(
            "/root/gryonixnexus-agent-src.tar.gz",
            AgentBootstrapOperations.expectedArchivePath(said),
        )
    }

    /** An absolute path and nothing else */
    @Test
    fun `a path that is not plainly absolute is refused`() {
        assertEquals(
            null,
            AgentBootstrapOperations.expectedArchivePath("no agent sources uploaded (relative/path)"),
        )
        assertEquals(
            null,
            AgentBootstrapOperations.expectedArchivePath("no agent sources uploaded (/has a space)"),
        )
    }

    @Test
    fun `both ways of saying the wrapper is missing are recognised`() {
        val path = AgentBootstrapSections.SCRIPT_PATH
        assertTrue(AgentBootstrapOperations.wrapperIsMissing("sudo: $path: command not found"))
        assertTrue(AgentBootstrapOperations.wrapperIsMissing("bash: $path: No such file or directory"))
        assertTrue(!AgentBootstrapOperations.wrapperIsMissing("error: could not compile gryonixnexusd"))
        assertTrue(!AgentBootstrapOperations.wrapperIsMissing("command not found: cargo"))
    }

    /** A write that fails names the PATH */
    @Test
    fun `a refused upload says where it was writing`() = runTest {
        val machine = object : Machine() {
            override suspend fun uploadFile(data: ByteArray, path: String, host: SSHHostID) {
                throw IllegalStateException("status 1")
            }
        }
        val failure = assertFailsWith<ServerControlError.NotConfigured> { install(machine) }
        assertTrue(
            failure.detail.contains("/home/gryonix/${AgentBootstrapSections.ARCHIVE_NAME}"),
            "the diagnosis is the path: ${failure.detail}",
        )
    }

    @Test
    fun `the build is started detached and its log followed`() = runTest {
        val machine = Machine(wrapperRuns = mutableListOf("built"))
        AgentBootstrapOperations.install(
            runner = machine, files = machine, host = SSHHostID.VPS, sources = sources,
            onPhase = quiet, onOutput = quiet,
        )
        assertTrue(machine.commands.any { "setsid nohup" in it }, "${machine.commands}")
        assertTrue(machine.commands.any { "tail -n +1" in it })
    }
}
