package com.skaymer.gryonixnexus.transport

import com.skaymer.gryonixnexus.servercontrol.ServerControlError
import java.security.KeyPairGenerator
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

class TerminalSessionTest {
    private lateinit var server: LocalSSHServer
    private val seed = ByteArray(32) { (it + 7).toByte() }

    private fun login() = TerminalLogin("owner", TerminalLogin.Secret.Password("s3cret"))

    private fun endpoint() = TerminalEndpoint(host = "127.0.0.1", port = server.port)

    private fun session(
        endpoint: TerminalEndpoint = endpoint(),
        login: TerminalLogin = login(),
        onPin: (String, String) -> Unit = { _, _ -> },
    ) = TerminalSession(endpoint, login, onPin)

    @BeforeEach
    fun startServer() {
        server = LocalSSHServer().apply {
            password = "s3cret"
            authorizedKey = SSHJCommandRunner.keyProvider(seed).public
            start()
        }
    }

    @AfterEach
    fun stopServer() = server.stop()

    private suspend fun CoroutineScope.collecting(
        terminal: TerminalSession,
        events: MutableList<TerminalEvent>,
    ): Job = launch(Dispatchers.IO) { terminal.output.collect { events += it } }

    private suspend fun await(events: List<TerminalEvent>, predicate: (List<TerminalEvent>) -> Boolean) {
        withTimeout(10_000) { while (!predicate(events)) delay(20) }
    }

    private fun text(events: List<TerminalEvent>) =
        events.filterIsInstance<TerminalEvent.Output>().joinToString("") { String(it.bytes) }

    private fun bytes(events: List<TerminalEvent>): ByteArray =
        events.filterIsInstance<TerminalEvent.Output>()
            .fold(ByteArray(0)) { all, event -> all + event.bytes }

    // ------------------------------------------------------------ The shell

    @Test
    fun `a shell opens and its output arrives as bytes`() = runBlocking {
        val terminal = session()
        val events = CopyOnWriteArrayList<TerminalEvent>()
        val collector = collecting(terminal, events)

        terminal.start(columns = 80, rows = 24)
        await(events) { text(it).contains("ready") }

        assertTrue(text(events).contains("ready"), text(events))
        terminal.close()
        collector.cancel()
    }

    /** Bytes, not text */
    @Test
    fun `what is typed reaches the far end and comes back`() = runBlocking {
        val terminal = session()
        val events = CopyOnWriteArrayList<TerminalEvent>()
        val collector = collecting(terminal, events)
        terminal.start(columns = 80, rows = 24)
        await(events) { text(it).contains("ready") }

        terminal.send("hello\n".toByteArray())
        await(events) { text(it).contains("hello") }

        assertTrue(text(events).contains("hello"), text(events))
        terminal.close()
        collector.cancel()
    }

    /** A terminal's output is not text */
    @Test
    fun `output is handed over as the bytes that arrived, not as decoded text`() = runBlocking {
        val terminal = session()
        val events = CopyOnWriteArrayList<TerminalEvent>()
        val collector = collecting(terminal, events)
        terminal.start(columns = 80, rows = 24)
        await(events) { text(it).contains("ready") }
        val ready = bytes(events).size

        val raw = byteArrayOf(0x1B, '['.code.toByte(), 'A'.code.toByte(), 0xFF.toByte(), 0xFE.toByte())
        terminal.send(raw)
        await(events) { bytes(it).size >= ready + raw.size }

        val echoed = bytes(events).copyOfRange(ready, ready + raw.size)
        assertTrue(raw.contentEquals(echoed), echoed.joinToString(" ") { "%02x".format(it) })
        terminal.close()
        collector.cancel()
    }

    @Test
    fun `the terminal size is part of the request that opens the shell`() = runBlocking {
        val terminal = session()
        val events = CopyOnWriteArrayList<TerminalEvent>()
        val collector = collecting(terminal, events)

        terminal.start(columns = 132, rows = 43)
        await(events) { text(it).contains("ready") }

        assertEquals(132, server.initialColumns)
        terminal.close()
        collector.cancel()
    }

    @Test
    fun `a resize reaches the far end without restarting anything`() = runBlocking {
        val terminal = session()
        val events = CopyOnWriteArrayList<TerminalEvent>()
        val collector = collecting(terminal, events)
        terminal.start(columns = 80, rows = 24)
        await(events) { text(it).contains("ready") }

        terminal.resize(columns = 100, rows = 30)
        withTimeout(10_000) { while (server.resizes.isEmpty()) delay(20) }

        assertEquals(100, server.resizes.first())
        assertEquals(1, server.connectionCount)
        terminal.close()
        collector.cancel()
    }

    /** Somebody typing `exit` is not a failure */
    @Test
    fun `a shell that exits on its own closes with no reason`() = runBlocking {
        val terminal = session()
        val events = CopyOnWriteArrayList<TerminalEvent>()
        val collector = collecting(terminal, events)
        terminal.start(columns = 80, rows = 24)
        await(events) { text(it).contains("ready") }

        terminal.send("exit\n".toByteArray())
        await(events) { it.any { event -> event is TerminalEvent.Closed } }

        val closed = events.filterIsInstance<TerminalEvent.Closed>().single()
        assertNull(closed.reason, "an ordinary exit must not be drawn as a failure")
        collector.cancel()
    }

    // ------------------------------------------------------------- Lifecycle

    @Test
    fun `a terminal cannot be started twice`() = runBlocking {
        val terminal = session()
        terminal.start(columns = 80, rows = 24)

        assertFailsWith<ServerControlError.NotConfigured> { terminal.start(80, 24) }

        terminal.close()
    }

    @Test
    fun `closing the terminal ends the stream`() = runBlocking {
        val terminal = session()
        val events = CopyOnWriteArrayList<TerminalEvent>()
        val collector = collecting(terminal, events)
        terminal.start(columns = 80, rows = 24)
        await(events) { text(it).contains("ready") }

        terminal.close()

        // The collector returns on its own: nobody cancels it here.
        withTimeout(10_000) { collector.join() }
    }

    @Test
    fun `a shell that exits on its own also ends the stream`() = runBlocking {
        val terminal = session()
        val events = CopyOnWriteArrayList<TerminalEvent>()
        val collector = collecting(terminal, events)
        terminal.start(columns = 80, rows = 24)
        await(events) { text(it).contains("ready") }

        terminal.send("exit\n".toByteArray())

        withTimeout(10_000) { collector.join() }
        assertTrue(
            events.last() is TerminalEvent.Closed,
            "the ending must be the last thing said, not lost with the stream: $events",
        )
    }

    @Test
    fun `closing twice is harmless`() = runBlocking {
        val terminal = session()
        terminal.start(columns = 80, rows = 24)
        terminal.close()
        terminal.close()
    }

    @Test
    fun `typing after the terminal closed is ignored`() = runBlocking {
        val terminal = session()
        terminal.start(columns = 80, rows = 24)
        terminal.close()

        terminal.send("still here?\n".toByteArray())
        terminal.resize(120, 40)
    }

    // ------------------------------------------------------------- Refusals

    @Test
    fun `a wrong password is an error the caller can show on its form`() = runBlocking {
        val terminal = session(login = TerminalLogin("owner", TerminalLogin.Secret.Password("wrong")))

        assertFailsWith<ServerControlError.ConnectionFailed> { terminal.start(80, 24) }
    }

    @Test
    fun `a private key login signs in with the seed it was given`() = runBlocking {
        server.password = null
        val terminal = session(
            login = TerminalLogin("owner", TerminalLogin.Secret.PrivateKeySeed(seed)),
        )
        val events = CopyOnWriteArrayList<TerminalEvent>()
        val collector = collecting(terminal, events)

        terminal.start(columns = 80, rows = 24)
        await(events) { text(it).contains("ready") }

        terminal.close()
        collector.cancel()
    }

    // ----------------------------------------------------------- Host keys

    @Test
    fun `a first-sight host key is reported against the host it belongs to`() = runBlocking {
        val pinned = CopyOnWriteArrayList<Pair<String, String>>()
        val terminal = session(onPin = { host, key -> pinned += host to key })

        terminal.start(columns = 80, rows = 24)
        withTimeout(10_000) { while (pinned.isEmpty()) delay(20) }

        assertEquals("127.0.0.1", pinned.single().first)
        assertTrue(pinned.single().second.startsWith("ssh-rsa "), pinned.single().second)
        terminal.close()
    }

    @Test
    fun `a host key that is not the pinned one is refused`() = runBlocking {
        val terminal = session(
            endpoint = endpoint().copy(pinnedHostKey = "ssh-ed25519 AAAAsomethingelse"),
        )

        assertFailsWith<ServerControlError.HostKeyMismatch> { terminal.start(80, 24) }
    }

    // ------------------------------------------------------------- The jump

    @Test
    fun `a jumped terminal reaches a machine only the hop can see`() = runBlocking {
        val far = LocalSSHServer().apply {
            password = "owners-own"
            start()
        }
        try {
            val pinned = CopyOnWriteArrayList<Pair<String, String>>()
            val terminal = TerminalSession(
                TerminalEndpoint(
                    host = "localhost",
                    port = far.port,
                    parent = TerminalEndpoint.Hop(
                        host = "127.0.0.1",
                        port = server.port,
                        pinnedHostKey = null,
                        login = login(),
                    ),
                ),
                TerminalLogin("owner", TerminalLogin.Secret.Password("owners-own")),
                onPinHostKey = { host, key -> pinned += host to key },
            )
            val events = CopyOnWriteArrayList<TerminalEvent>()
            val collector = collecting(terminal, events)

            terminal.start(columns = 80, rows = 24)
            await(events) { text(it).contains("ready") }

            assertEquals(1, far.connectionCount)
            assertTrue(text(events).contains("ready"), text(events))
            assertEquals(
                setOf("127.0.0.1" to server.hostKeyLine, "localhost" to far.hostKeyLine),
                pinned.toSet(),
                "$pinned",
            )

            terminal.close()
            collector.cancel()
        } finally {
            far.stop()
        }
    }

    @Test
    fun `the hop and its forwarded socket go when the terminal does`() = runBlocking {
        val far = LocalSSHServer().apply {
            password = "owners-own"
            start()
        }
        try {
            val terminal = TerminalSession(
                TerminalEndpoint(
                    host = "localhost",
                    port = far.port,
                    parent = TerminalEndpoint.Hop(
                        host = "127.0.0.1",
                        port = server.port,
                        pinnedHostKey = null,
                        login = login(),
                    ),
                ),
                TerminalLogin("owner", TerminalLogin.Secret.Password("owners-own")),
            )
            val events = CopyOnWriteArrayList<TerminalEvent>()
            val collector = collecting(terminal, events)
            terminal.start(columns = 80, rows = 24)
            await(events) { text(it).contains("ready") }
            assertEquals(1, server.liveConnectionCount, "the hop should be carrying the terminal")

            terminal.close()

            withTimeout(10_000) { while (server.liveConnectionCount > 0) delay(20) }
            assertEquals(0, server.liveConnectionCount)
            collector.cancel()
        } finally {
            far.stop()
        }
    }
}
