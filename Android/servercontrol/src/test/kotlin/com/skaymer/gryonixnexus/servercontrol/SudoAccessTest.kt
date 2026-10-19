package com.skaymer.gryonixnexus.servercontrol

import java.io.File
import java.nio.file.Files
import java.util.concurrent.TimeUnit
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class SudoAccessTest {
    @Test
    fun `the probe token is read only as a whole line`() {
        assertTrue(SudoAccess.isReady("GRYONIXNEXUS_PING\nGRYONIXNEXUS_SUDO_OK\n"))
        assertFalse(SudoAccess.isReady("echo GRYONIXNEXUS_SUDO_OK_NOT"))
        assertFalse(SudoAccess.isReady(""))
    }

    @Test
    fun `an insult in place of sorry is still a wrong password`() {
        val insult = ExecResult(1, "", "sudo: I'm sorry server-user. I'm afraid I can't do that\n")
        assertEquals(SudoAccess.Outcome.WrongPassword, SudoAccess.outcome(insult))
    }

    @Test
    fun `a locked account is told apart from an open one`() {
        assertTrue(SudoAccess.passwordIsLocked("GRYONIXNEXUS_PASSWORD=L\n"))
        assertTrue(SudoAccess.passwordIsLocked("GRYONIXNEXUS_PASSWORD=NP\n"))
        assertFalse(SudoAccess.passwordIsLocked("GRYONIXNEXUS_PASSWORD=P\n"))
        assertFalse(SudoAccess.passwordIsLocked(""))
    }

    @Test
    fun `the agent probe accepts a whitelisted wrapper`() {
        val probe = SudoAccess.probeCommand("/opt/gryonixnexus-agent-bootstrap.sh")
        assertTrue("sudo -n -l '/opt/gryonixnexus-agent-bootstrap.sh'" in probe)
        assertTrue("passwd -S" in probe)
    }

    @Test
    fun `sudo wordings map to outcomes`() {
        fun outcome(code: Int, out: String, err: String) =
            SudoAccess.outcome(ExecResult(code, out, err))
        assertEquals(SudoAccess.Outcome.Granted, outcome(0, "GRYONIXNEXUS_SUDO_OK\n", ""))
        assertEquals(SudoAccess.Outcome.WrongPassword,
            outcome(1, "", "Sorry, try again.\nsudo: 1 incorrect password attempt\n"))
        assertEquals(SudoAccess.Outcome.WrongPassword, outcome(1, "", "sudo: no password was provided\n"))
        assertEquals(SudoAccess.Outcome.NotAllowed, outcome(1, "", "anna is not in the sudoers file.\n"))
        assertEquals(SudoAccess.Outcome.NotAllowed,
            outcome(1, "", "Sorry, user anna is not allowed to run sudo on draco.\n"))
        assertEquals(SudoAccess.Outcome.Failed("visudo: parse error"), outcome(3, "", "visudo: parse error\n"))
    }

    @Test
    fun `a newer sudo refusal reads as a password prompt`() {
        assertTrue(ServerControlError.stderrAsksForASudoPassword(
            "sudo: interactive authentication is required\n"))
    }

    @Test
    fun `the password goes by file and never into a command`() = runTest {
        val runner = FakeFileRunner()
        runner.stub("mktemp -d", stdout = "/tmp/tmp.AbC123\n")
        runner.stub("sudo -S", stdout = "GRYONIXNEXUS_SUDO_OK\n")
        val outcome = SudoAccess.grant("s3cret pass", runner, runner, SSHHostID.VPS)

        assertEquals(SudoAccess.Outcome.Granted, outcome)
        assertEquals(listOf("/tmp/tmp.AbC123/p"), runner.uploads.map { it.first })
        assertEquals("s3cret pass\n", runner.uploads.single().second.decodeToString())
        assertFalse(runner.calls.any { "s3cret" in it.command })
        assertTrue(runner.calls.last().command.endsWith("rm -rf '/tmp/tmp.AbC123'; exit \$rc"))
    }

    @Test
    fun `a failed upload still removes the directory`() = runTest {
        val runner = FakeFileRunner()
        runner.stub("mktemp -d", stdout = "/tmp/tmp.X\n")
        runner.uploadError = IllegalStateException("sftp")
        assertFailsWith<IllegalStateException> { SudoAccess.grant("p", runner, runner, SSHHostID.VPS) }
        assertEquals("rm -rf '/tmp/tmp.X'", runner.calls.last().command)
    }

    @Test
    fun `the grant line writes the drop-in and wipes the password`() {
        val work = Files.createTempDirectory("gryonix-sudo").toFile()
        try {
            val bin = File(work, "bin").apply { mkdirs() }
            val drop = File(work, "sudoers.d").apply { mkdirs() }
            val staging = File(work, "stage").apply { mkdirs() }
            File(staging, "p").writeText("right\n")
            script(File(bin, "sudo"), """
                #!/bin/sh
                read -r pw
                [ "${'$'}pw" = right ] || { echo "sudo: 1 incorrect password attempt" >&2; exit 1; }
                while [ "${'$'}1" != "-c" ]; do shift; done
                body=${'$'}(printf %s "${'$'}2" | sed "s#/etc/sudoers.d#${'$'}DROP#g")
                SUDO_USER=anna.b exec sh -c "${'$'}body"
            """.trimIndent() + "\n")
            script(File(bin, "visudo"), "#!/bin/sh\nexit 0\n")

            val process = ProcessBuilder("/bin/sh", "-c", SudoAccess.grantCommand(staging.path)).apply {
                environment()["PATH"] = "${bin.path}:/usr/bin:/bin"
                environment()["DROP"] = drop.path
            }.start()
            process.waitFor(30, TimeUnit.SECONDS)
            val result = ExecResult(process.exitValue(),
                process.inputStream.bufferedReader().readText(),
                process.errorStream.bufferedReader().readText())

            assertEquals(SudoAccess.Outcome.Granted, SudoAccess.outcome(result))
            assertEquals("anna.b ALL=(ALL) NOPASSWD:ALL\n", File(drop, "gryonixnexus-anna_b").readText())
            assertFalse(staging.exists())
        } finally {
            work.deleteRecursively()
        }
    }

    private fun script(file: File, text: String) {
        file.writeText(text)
        file.setExecutable(true)
    }
}

/** A fake runner that also records SFTP uploads */
private class FakeFileRunner : FakeSSHCommandRunner(), RemoteFileBrowser {
    val uploads = mutableListOf<Pair<String, ByteArray>>()
    var uploadError: Exception? = null

    override suspend fun homeDirectory(host: SSHHostID) = "/home/anna"
    override suspend fun listDirectory(path: String, host: SSHHostID) = emptyList<RemoteFileEntry>()
    override suspend fun downloadFile(path: String, host: SSHHostID, maxBytes: Long) = ByteArray(0)
    override suspend fun deleteFile(entry: RemoteFileEntry, host: SSHHostID) {}

    override suspend fun uploadFile(data: ByteArray, path: String, host: SSHHostID) {
        uploadError?.let { throw it }
        uploads += path to data
    }
}
