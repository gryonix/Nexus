package com.skaymer.gryonixnexus.transport

import com.skaymer.gryonixnexus.servercontrol.ExecChunk
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.ServerControlError
import java.security.KeyPairGenerator
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Timeout

class SSHJCommandRunnerTest {
    private lateinit var server: LocalSSHServer
    private val host = SSHHostID.VPS

    private val seed = ByteArray(32) { it.toByte() }

    private fun settings(password: String? = null) = SSHConnectionSettings(
        vpsHost = "127.0.0.1",
        vpsPort = server.port,
        username = "owner",
        homeHost = "10.8.0.2",
        privateKeySeed = seed,
        passwords = password?.let { mapOf(host to it) } ?: emptyMap(),
    )

    private fun runner(password: String? = null): SSHJCommandRunner {
        val settings = settings(password)
        return SSHJCommandRunner(settings) { _, forHost -> server.client(settings, forHost) }
    }

    @BeforeEach
    fun startServer() {
        server = LocalSSHServer().apply {
            authorizedKey = KeyPairGenerator.getInstance("Ed25519").let {
                SSHJCommandRunner.keyProvider(seed).public
            }
            start()
        }
    }

    @AfterEach
    fun stopServer() {
        server.stop()
    }

    // ------------------------------------------------------------------ run

    @Test
    fun `a command's output and exit code come back`() = runBlocking {
        server.script("echo hello", LocalSSHServer.Reply(stdout = "hello\n"))

        val result = runner().run("echo hello", host, 10.seconds)

        assertEquals(0, result.exitCode)
        assertEquals("hello\n", result.stdout)
        assertTrue(result.succeeded)
        assertEquals(listOf("echo hello"), server.commands)
    }

    /**
     * **A command that FILLS both pipes still comes back**, and the small tests
     * above say nothing about it.
     *
     * A few bytes fit in a buffer, so reading stdout to EOF and then stderr
     * works — and so would awaiting the exit status first. The deadlock needs
     * the far side to fill the pipe nobody is draining, which is what a backup
     * does: tarring to stdout while writing progress to stderr. The reader waits
     * for stdout to end; the server waits for somebody to take stderr.
     *
     * Found on the gryonixVPN port, where this code was carried over: 3 MB down
     * both pipes hung a whole run. **`withTimeout` does not rescue it** —
     * cancellation is cooperative and a blocking `read` never checks — so
     * nothing returns at all, including the deadline the app believes in. Hence
     * the JUnit one here — and on a SEPARATE THREAD, which is the half that
     * matters. A plain `@Timeout` does not interrupt anything: it runs the test
     * inline and checks the elapsed time AFTER it returns, so on a test that
     * never returns it never fires. Learned by watching two control runs hang
     * for ten minutes and leave the tree patched.
     */
    @Test
    @Timeout(value = 90, unit = java.util.concurrent.TimeUnit.SECONDS,
             threadMode = Timeout.ThreadMode.SEPARATE_THREAD)
    fun `a command that fills both pipes still completes`() = runBlocking {
        val bulk = "x".repeat(3 * 1024 * 1024)
        server.script("dump", LocalSSHServer.Reply(stdout = bulk, stderr = bulk))

        val result = runner().run("dump", host, 60.seconds)

        assertEquals(0, result.exitCode)
        assertEquals(bulk.length, result.stdout.length, "stdout was truncated")
        assertEquals(bulk.length, result.stderr.length, "stderr was truncated")
    }

    /**
     * stderr and a non-zero exit are the pair every caller in `:servercontrol`
     * branches on — a runner that returned only stdout would make every failure
     * look like an empty success.
     */
    @Test
    fun `a failing command reports its stderr and its code`() = runBlocking {
        server.script("bad", LocalSSHServer.Reply(stderr = "no such thing\n", exitCode = 3))

        val result = runner().run("bad", host, 10.seconds)

        assertEquals(3, result.exitCode)
        assertEquals("no such thing\n", result.stderr)
        assertTrue(!result.succeeded)
    }

    @Test
    fun `stdout and stderr do not bleed into each other`() = runBlocking {
        server.script("both", LocalSSHServer.Reply(stdout = "out", stderr = "err"))

        val result = runner().run("both", host, 10.seconds)

        assertEquals("out", result.stdout)
        assertEquals("err", result.stderr)
    }

    // -------------------------------------------------------------- Auth

    /**
     * **Auth is chosen by MACHINE.** A host the settings hold a password for is
     * signed in to with it; everything else uses the deployment's own key. Both
     * are asserted against a server that accepts only one of them at a time, so
     * "it connected" cannot be true by accident.
     */
    @Test
    fun `a host with a password signs in with it`() = runBlocking {
        server.authorizedKey = null
        server.password = "s3cret"
        server.script("id", LocalSSHServer.Reply(stdout = "owner\n"))

        assertEquals("owner\n", runner(password = "s3cret").run("id", host, 10.seconds).stdout)
    }

    @Test
    fun `a host with no password signs in with the app key`() = runBlocking {
        server.password = null // key only
        server.script("id", LocalSSHServer.Reply(stdout = "owner\n"))

        assertEquals("owner\n", runner().run("id", host, 10.seconds).stdout)
    }

    // ------------------------------------------------------------- Sessions

    /** One session per machine, reused */
    @Test
    fun `one connection serves many commands`() = runBlocking {
        server.script("a", LocalSSHServer.Reply(stdout = "1"))
        server.script("b", LocalSSHServer.Reply(stdout = "2"))
        val runner = runner()

        runner.run("a", host, 10.seconds)
        runner.run("b", host, 10.seconds)

        assertEquals(1, server.connectionCount, "each command opened its own connection")
        assertEquals(listOf("a", "b"), server.commands)
    }

    @Test
    fun `no more channels are open at once than sshd allows`() = runBlocking {
        server.script("slow", LocalSSHServer.Reply(stdout = "done", delayMillis = 60))
        val runner = runner()

        val jobs = (0 until 12).map {
            launch(Dispatchers.IO) { runner.run("slow", host, 20.seconds) }
        }
        jobs.forEach { it.join() }

        assertTrue(
            server.peakConcurrentChannels <= SSHJCommandRunner.MAX_CONCURRENT_CHANNELS,
            "peaked at ${server.peakConcurrentChannels} channels",
        )
        assertTrue(
            server.peakConcurrentChannels > 1,
            "nothing overlapped — the cap was not actually exercised",
        )
        assertEquals(12, server.commands.size)
    }

    // ---------------------------------------------------------------- Stdin

    @Test
    fun `a secret travels on stdin and the command sees its end`() = runBlocking {
        server.script("read-secret", LocalSSHServer.Reply(echoesStdin = true))

        val result = runner().run("read-secret", "pässwort 'quoted'", host, 10.seconds)

        assertEquals("pässwort 'quoted'", result.stdout)
        assertEquals(listOf("read-secret"), server.commands)
    }

    @Test
    fun `streamed text survives multi-byte characters across reads`() = runBlocking {
        val text = "Резервная копия готова. ".repeat(2_000)
        server.script("long-report", LocalSSHServer.Reply(stdout = text))

        val received = runner().stream("long-report", host, 30.seconds).toList()
            .joinToString("") { it.text }

        assertEquals(text, received)
    }

    // -------------------------------------------------------------- Timeout

    @Test
    fun `a command that outruns its deadline times out`() = runBlocking {
        server.script("forever", LocalSSHServer.Reply(stdout = "x", delayMillis = 3_000))

        val error = assertFailsWith<ServerControlError.Timeout> {
            runner().run("forever", host, 1.seconds)
        }
        assertEquals("forever", error.command)
    }

    /** Only its channel goes; the other commands keep the connection */
    @Test
    fun `a timeout closes its channel and keeps the connection`() = runBlocking {
        server.script("forever", LocalSSHServer.Reply(stdout = "x", delayMillis = 3_000))
        server.script("after", LocalSSHServer.Reply(stdout = "ok"))
        val runner = runner()

        runCatching { runner.run("forever", host, 1.seconds) }
        assertEquals("ok", runner.run("after", host, 10.seconds).stdout)

        assertEquals(1, server.connectionCount, "a live connection should have been reused")
    }

    // --------------------------------------------------------------- stream

    @Test
    fun `a streamed command yields what each pipe produced`() = runBlocking {
        server.script("work", LocalSSHServer.Reply(stdout = "progress\n", stderr = "warning\n"))

        val chunks = runner().stream("work", host, 10.seconds).toList()

        assertEquals("progress\n", chunks.filterIsInstance<ExecChunk.Stdout>().joinToString("") { it.text })
        assertEquals("warning\n", chunks.filterIsInstance<ExecChunk.Stderr>().joinToString("") { it.text })
    }

    @Test
    fun `a silent command completes its stream`() = runBlocking {
        server.script("quiet", LocalSSHServer.Reply())
        assertTrue(runner().stream("quiet", host, 10.seconds).toList().isEmpty())
    }

    // -------------------------------------------------------- fireAndForget

    @Test
    fun `a fire-and-forget command returns without waiting for it to finish`() = runBlocking {
        server.script("restart-wg", LocalSSHServer.Reply(delayMillis = 3_000))

        val started = System.nanoTime()
        runner().fireAndForget("restart-wg", host)
        val elapsedMillis = (System.nanoTime() - started) / 1_000_000

        assertTrue(elapsedMillis < 2_000, "it waited ${elapsedMillis}ms for a 3s command")
        assertTrue(server.commands.contains("restart-wg"), "the command never reached the server")
    }

    // ----------------------------------------------------------- disconnect

    @Test
    fun `disconnect closes the session and a later command opens a new one`() = runBlocking {
        server.script("a", LocalSSHServer.Reply(stdout = "1"))
        val runner = runner()

        runner.run("a", host, 10.seconds)
        runner.disconnect()
        runner.run("a", host, 10.seconds)

        assertEquals(2, server.connectionCount)
    }

    // ------------------------------------------------------------- Refusals

    @Test
    fun `a host with no route is refused before anything is dialled`() = runBlocking {
        val error = assertFailsWith<ServerControlError.NotConfigured> {
            runner().run("id", SSHHostID.node("a-machine-nobody-described"), 10.seconds)
        }
        assertTrue(error.message.orEmpty().contains("no address"), error.message.orEmpty())
        assertEquals(0, server.connectionCount)
    }
}
