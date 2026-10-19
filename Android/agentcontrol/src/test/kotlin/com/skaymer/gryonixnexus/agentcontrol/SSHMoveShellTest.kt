package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.servercontrol.ExecChunk
import com.skaymer.gryonixnexus.servercontrol.ExecResult
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import java.io.File
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.time.Duration
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.runTest

private class LocalRunner(private val home: File) : SSHCommandRunner {
    override suspend fun run(command: String, host: SSHHostID, timeout: Duration): ExecResult {
        val builder = ProcessBuilder("/bin/sh", "-c", command)
        builder.environment().clear()
        builder.environment()["HOME"] = home.path
        builder.environment()["PATH"] = "/usr/bin:/bin"
        val process = builder.start()
        val out = process.inputStream.readBytes().decodeToString()
        val err = process.errorStream.readBytes().decodeToString()
        return ExecResult(process.waitFor(), out, err)
    }

    override fun stream(command: String, host: SSHHostID, timeout: Duration): Flow<ExecChunk> = emptyFlow()
    override suspend fun fireAndForget(command: String, host: SSHHostID) = Unit
    override suspend fun disconnect() = Unit
}

class SSHMoveShellTest {
    private fun shell(home: File) = SSHMoveShell(LocalRunner(home), SSHHostID.VPS, "admin")

    private fun keys(home: File) = File(home, ".ssh/authorized_keys").readText()

    private fun newHome(): File = Files.createTempDirectory("move-shell").toFile()

    @Test
    fun `the key line is appended beside the keys already there`() = runTest {
        val home = newHome()
        File(home, ".ssh").mkdirs()
        File(home, ".ssh/authorized_keys").writeText("ssh-ed25519 OLD owner\n")
        val line = "restrict,command=\"cat > /var/lib/gryonixnexus/incoming/ab/data.tar\" ssh-ed25519 NEW gryonixnexus-move-ab"
        shell(home).appendAuthorizedKey(line)
        assertEquals("ssh-ed25519 OLD owner\n$line\n", keys(home))
    }

    @Test
    fun `removing the line leaves the other keys alone`() = runTest {
        val home = newHome()
        val shell = shell(home)
        shell.appendAuthorizedKey("ssh-ed25519 ONE gryonixnexus-move-aa")
        shell.appendAuthorizedKey("ssh-ed25519 TWO owner")
        shell.appendAuthorizedKey("ssh-ed25519 THREE gryonixnexus-move-bb")
        shell.removeAuthorizedKeys("gryonixnexus-move-aa")
        assertEquals("ssh-ed25519 TWO owner\nssh-ed25519 THREE gryonixnexus-move-bb\n", keys(home))
        shell.removeAuthorizedKeys("gryonixnexus-move-aa")
        shell.removeAuthorizedKeys("gryonixnexus-move-bb")
        assertEquals("ssh-ed25519 TWO owner\n", keys(home))
    }

    @Test
    fun `removing from a machine with no key file is not an error`() = runTest {
        shell(newHome()).removeAuthorizedKeys("gryonixnexus-move-aa")
    }

    @Test
    fun `a quote in the line cannot break out of the command`() = runTest {
        val home = newHome()
        val line = "ssh-ed25519 A'; touch ${home.path}/pwned; echo '"
        shell(home).appendAuthorizedKey(line)
        assertEquals(line + "\n", keys(home))
        assertFalse(File(home, "pwned").exists())
    }
}
