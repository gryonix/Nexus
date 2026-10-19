package com.skaymer.gryonixnexus.servercontrol

import java.io.File
import java.nio.file.Files
import java.nio.file.attribute.PosixFilePermissions
import java.util.concurrent.TimeUnit
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.time.Duration
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

/** Runs [SetupInstaller]'s ACTUAL generated commands through a real shell */
class SetupInstallShellTest {
    private lateinit var work: File

    private val fileName = "it's a setup.sh"

    @BeforeEach
    fun setUp() {
        work = Files.createTempDirectory("gryonix-install").toFile()
        installGNUBase64Shim()
    }

    @AfterEach
    fun tearDown() {
        work.deleteRecursively()
    }

    /** The scripts target Debian, where `base64 -d FILE` reads FILE */
    private fun installGNUBase64Shim() {
        if (!File("/usr/bin/base64").exists()) return
        val bin = File(work, "bin").apply { mkdirs() }
        val shim = File(bin, "base64")
        shim.writeText(
            """
            #!/bin/bash
            last="${'$'}{@: -1}"
            if [ "${'$'}#" -gt 0 ] && [ -f "${'$'}last" ]; then
              exec /usr/bin/base64 "${'$'}{@:1:${'$'}#-1}" -i "${'$'}last"
            fi
            exec /usr/bin/base64 "${'$'}@"
            """.trimIndent(),
        )
        shim.setExecutable(true)
    }

    private fun shimmedPath(): String =
        File(work, "bin").path + ":" + (System.getenv("PATH") ?: "/usr/bin:/bin")

    private fun bash(command: String): String {
        val process = ProcessBuilder("/bin/bash", "-c", command)
            .directory(work)
            .redirectErrorStream(true)
            .also { it.environment()["PATH"] = shimmedPath() }
            .start()
        val text = process.inputStream.readBytes().decodeToString()
        process.waitFor(30, TimeUnit.SECONDS)
        return text
    }

    private fun writeScript(body: String) {
        File(work, fileName).writeText(body)
    }

    private suspend fun capturedLaunchCommand(): String {
        val fake = FakeSSHCommandRunner()
        fake.stub("cat > ")
        fake.stub("setsid")
        fake.stub("wc -l", stdout = "GRYONIXNEXUS_DONE\nGRYONIXNEXUS_EXIT:0\n")
        fake.stub("rm -f")
        SetupInstaller(fake, sleeper = FakeSleeper()).install("x\n", fileName).toList()
        return fake.calls.map { it.command }.first { it.contains("DETACH") }
    }

    @Test
    fun `the generated launch command runs the script`() = runTest {
        writeScript(
            """
            #!/usr/bin/env bash
            echo "GRYONIXNEXUS_STEP 1/1"
            echo "==> Firewall"
            echo "GRYONIXNEXUS_DONE"
            """.trimIndent(),
        )
        bash(capturedLaunchCommand())
        Thread.sleep(600)
        val log = File(work, "$fileName.log").readText()
        assertTrue(log.contains("GRYONIXNEXUS_STEP 1/1"), "log was not produced: [$log]")
        assertTrue(log.contains("GRYONIXNEXUS_DONE"))
        assertTrue(log.contains("GRYONIXNEXUS_EXIT:0"), "exit sentinel missing: [$log]")
    }

    @Test
    fun `the generated launch command reports a non-zero exit`() = runTest {
        writeScript("#!/usr/bin/env bash\necho boom >&2\nexit 7\n")
        bash(capturedLaunchCommand())
        Thread.sleep(600)
        val log = File(work, "$fileName.log").readText()
        assertTrue(log.contains("boom"), "stderr must land in the log too")
        assertTrue(log.contains("GRYONIXNEXUS_EXIT:7"), "wrong sentinel: [$log]")
    }

    @Test
    fun `the launcher does not leak its umask into the script`() = runTest {
        writeScript("#!/usr/bin/env bash\numask > umask.txt\n")
        val ambient = bash("umask").trim()
        bash(capturedLaunchCommand())
        Thread.sleep(600)
        assertEquals(
            ambient,
            File(work, "umask.txt").readText().trim(),
            "the launcher's 077 leaked into the run",
        )
        val log = File(work, "$fileName.log")
        assertEquals(
            "rw-------",
            PosixFilePermissions.toString(Files.getPosixFilePermissions(log.toPath())),
            "the run log must stay private",
        )
    }

    @Test
    fun `the generated follow command resumes at an offset and exits`() {
        File(work, "$fileName.log").writeText("one\ntwo\nthree\nGRYONIXNEXUS_EXIT:0\n")

        assertEquals(
            "one\ntwo\nthree\nGRYONIXNEXUS_EXIT:0\n",
            bash(SetupInstaller.followCommand(fileName, fromLine = 1)),
        )
        assertEquals(
            "three\nGRYONIXNEXUS_EXIT:0\n",
            bash(SetupInstaller.followCommand(fileName, fromLine = 3)),
            "resume must start exactly at the requested line",
        )
    }

    @Test
    fun `a whole install runs through a real shell`() = runTest {
        val runner = LocalShellRunner(work, shimmedPath())
        val script = """
            #!/usr/bin/env bash
            echo "GRYONIXNEXUS_STEP 1/2"
            echo "==> Firewall"
            echo "GRYONIXNEXUS_STEP 2/2"
            echo "GRYONIXNEXUS_REPORT_BEGIN"
            echo "Password: hunter2"
            echo "GRYONIXNEXUS_REPORT_END"
            echo "GRYONIXNEXUS_DONE"

        """.trimIndent() + "\n"

        val events = SetupInstaller(runner, sleeper = FakeSleeper())
            .install(script, fileName)
            .toList()

        assertTrue(events.contains(SetupEvent.Step(1, 2)))
        assertTrue(events.contains(SetupEvent.Stage("Firewall")))
        assertTrue(events.contains(SetupEvent.Report("Password: hunter2")))
        assertEquals(SetupEvent.Done, events.last())
        assertFalse(
            events.any { it is SetupEvent.Line && it.text.contains("GRYONIXNEXUS_EXIT") },
        )
        assertFalse(File(work, fileName).exists())
        assertFalse(File(work, "$fileName.log").exists())
    }

    @Test
    fun `an install survives a dropped follower and resumes`() = runTest {
        val runner = LocalShellRunner(work, shimmedPath())
        runner.failStreamAttempts = setOf(1)
        val script = """
            #!/usr/bin/env bash
            echo "GRYONIXNEXUS_STEP 1/2"
            sleep 2
            echo "GRYONIXNEXUS_STEP 2/2"
            echo "GRYONIXNEXUS_DONE"

        """.trimIndent() + "\n"

        val events = SetupInstaller(runner, sleeper = FakeSleeper())
            .install(script, fileName)
            .toList()

        assertTrue(events.contains(SetupEvent.Reconnecting(1)), "the drop must be visible")
        assertTrue(events.contains(SetupEvent.Step(1, 2)))
        assertTrue(events.contains(SetupEvent.Step(2, 2)), "output after the drop was lost")
        assertEquals(SetupEvent.Done, events.last())
        // Nothing delivered twice across the seam.
        assertEquals(
            2,
            events.count { it is SetupEvent.Step },
            "lines were duplicated across the re-attach",
        )
    }
}

private class LocalShellRunner(
    private val directory: File,
    private val path: String,
) : SSHCommandRunner {
    private var streamAttempt = 0

    var failStreamAttempts: Set<Int> = emptySet()

    private fun builder(command: String) = ProcessBuilder("/bin/bash", "-c", command)
        .directory(directory)
        .also { it.environment()["PATH"] = path }

    override suspend fun run(command: String, secret: String, host: SSHHostID, timeout: Duration): ExecResult =
        execute(command, secret)

    override suspend fun run(command: String, host: SSHHostID, timeout: Duration): ExecResult =
        execute(command, "")

    private fun execute(command: String, stdin: String): ExecResult {
        val process = builder(command).start()
        process.outputStream.use { it.write(stdin.toByteArray()) }
        val out = process.inputStream.readBytes().decodeToString()
        val err = process.errorStream.readBytes().decodeToString()
        process.waitFor(60, TimeUnit.SECONDS)
        return ExecResult(process.exitValue(), out, err)
    }

    override fun stream(command: String, host: SSHHostID, timeout: Duration): Flow<ExecChunk> {
        streamAttempt += 1
        val cutOff = failStreamAttempts.contains(streamAttempt)
        return callbackFlow {
            val process = builder(command).redirectErrorStream(true).start()
            val worker = Thread {
                try {
                    val buffer = ByteArray(8192)
                    while (true) {
                        val read = process.inputStream.read(buffer)
                        if (read <= 0) break
                        trySend(ExecChunk.Stdout(String(buffer, 0, read, Charsets.UTF_8)))
                        if (cutOff) {
                            process.destroy()
                            break
                        }
                    }
                    process.waitFor(60, TimeUnit.SECONDS)
                } finally {
                    close()
                }
            }
            worker.start()
            awaitClose { process.destroy() }
        }
    }

    override suspend fun fireAndForget(command: String, host: SSHHostID) {
        run(command, host, Duration.ZERO)
    }

    override suspend fun disconnect() {}
}
