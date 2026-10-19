package com.skaymer.gryonixnexus.transport

import java.net.ServerSocket
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import net.schmizz.sshj.transport.verification.PromiscuousVerifier
import org.junit.jupiter.api.Test

class SSHClientsTest {
    @Test
    fun `a silent hang-up is redialled, then explained`() {
        val listener = ServerSocket(0)
        val accepted = AtomicInteger(0)
        thread(isDaemon = true) {
            while (!listener.isClosed) {
                runCatching { listener.accept().close(); accepted.incrementAndGet() }
            }
        }
        try {
            val failure = assertFailsWith<java.io.IOException> {
                SSHClients.redialing(pauses = listOf(10L, 10L)) {
                    SSHClients.signIn(SSHClients.create()) { connect("127.0.0.1", listener.localPort) }
                }
            }
            assertTrue(failure.message.orEmpty().contains("before answering"), failure.message)
            assertEquals(3, accepted.get())
        } finally {
            listener.close()
        }
    }

    @Test
    fun `a refused sign-in closes the socket at once`() {
        val server = LocalSSHServer().apply { password = "right" }.start()
        try {
            val client = SSHClients.create().apply { addHostKeyVerifier(PromiscuousVerifier()) }
            assertFailsWith<Exception> {
                SSHClients.signIn(client) {
                    connect("127.0.0.1", server.port)
                    authPassword("user", "wrong")
                }
            }
            repeat(40) { if (server.closedSessionCount == 0) Thread.sleep(50) }
            assertEquals(1, server.closedSessionCount, "the server must not wait out its login grace time")
        } finally {
            server.stop()
        }
    }
}
