package com.skaymer.gryonixnexus.transport

import com.skaymer.gryonixnexus.agentclient.AgentByteStream
import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.agentclient.ConnectEnvelope
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

/** The failure this transport exists to explain */
class SSHAgentTransportTest {
    private class FakeChannel(response: ByteArray, private val stderr: String) : BridgeChannel {
        var closed = false
        val written = mutableListOf<ByteArray>()

        private var remaining = response
        override val stream: AgentByteStream = object : AgentByteStream {
            override suspend fun write(data: ByteArray) { written += data }
            override suspend fun read(): ByteArray {
                val out = remaining
                remaining = ByteArray(0)
                return out
            }
            override suspend fun close() {}
        }

        override val stderrText: String get() = stderr
        override suspend fun close() { closed = true }
    }

    private class FakeFactory(val channel: FakeChannel) : BridgeChannelFactory {
        var command: String? = null
        override suspend fun open(command: String): BridgeChannel {
            this.command = command
            return channel
        }
    }

    private fun okResponse(body: ByteArray) =
        ("HTTP/1.1 200 OK\r\nContent-Length: ${body.size}\r\n\r\n").toByteArray() + body

    private fun chunkedStream(frames: List<ByteArray>, trailer: String): ByteArray {
        val body = frames.fold(ByteArray(0)) { acc, f -> acc + ConnectEnvelope.encode(f) } +
            ConnectEnvelope.encode(trailer.toByteArray(), ConnectEnvelope.END_OF_STREAM_FLAG)
        return ("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n" +
            body.size.toString(16) + "\r\n").toByteArray() + body + "\r\n0\r\n\r\n".toByteArray()
    }

    @Test
    fun `a bridge that could not start reports what the server said`() = runTest {
        val channel = FakeChannel(ByteArray(0), "sudo: a password is required")
        val transport = SSHAgentTransport(FakeFactory(channel))

        val error = assertFailsWith<AgentError.Transport> {
            transport.unary("/gryonixnexusd.v1.Control/GetState", ByteArray(0))
        }
        assertTrue(
            error.detail.contains("sudo: a password is required"),
            "the reason must survive to the caller, got: ${error.detail}",
        )
        assertTrue(channel.closed, "the channel is closed even when the RPC failed")
    }

    @Test
    fun `a stream whose bridge could not start reports it too`() = runTest {
        val channel = FakeChannel(ByteArray(0), "gryonixnexusd: command not found")
        val transport = SSHAgentTransport(FakeFactory(channel))

        val error = assertFailsWith<AgentError.Transport> {
            transport.serverStream("/gryonixnexusd.v1.Install/WatchInstall", ByteArray(0)).toList()
        }
        assertTrue(error.detail.contains("command not found"), error.detail)
    }

    @Test
    fun `an answer from the agent is not overwritten by stderr noise`() = runTest {
        val body = """{"code":"failed_precondition","message":"no installer for that id yet"}"""
        val response = ("HTTP/1.1 422 Unprocessable Entity\r\nContent-Length: ${body.length}\r\n\r\n" +
            body).toByteArray()
        val channel = FakeChannel(response, "warning: something on stderr")
        val transport = SSHAgentTransport(FakeFactory(channel))

        val error = assertFailsWith<AgentError.Rpc> {
            transport.unary("/gryonixnexusd.v1.Install/InstallService", ByteArray(0))
        }
        assertEquals("failed_precondition", error.code)
        assertTrue(
            !error.text.contains("something on stderr"),
            "a refusal from the agent must keep its own words",
        )
    }

    @Test
    fun `a unary call runs the bridge command and returns the body`() = runTest {
        val channel = FakeChannel(okResponse(byteArrayOf(4, 2)), "")
        val factory = FakeFactory(channel)

        val out = SSHAgentTransport(factory).unary("/gryonixnexusd.v1.Control/GetState", byteArrayOf(1))

        assertContentEquals(byteArrayOf(4, 2), out)
        assertEquals(SSHAgentTransport.DEFAULT_BRIDGE_COMMAND, factory.command)
        assertTrue(channel.closed)
    }

    @Test
    fun `the bridge command can be given by the caller`() = runTest {
        val factory = FakeFactory(FakeChannel(okResponse(ByteArray(0)), ""))
        SSHAgentTransport(factory, "sudo -n /opt/custom/gryonixnexusd bridge")
            .unary("/gryonixnexusd.v1.Control/Discover", ByteArray(0))
        assertEquals("sudo -n /opt/custom/gryonixnexusd bridge", factory.command)
    }

    @Test
    fun `a stream yields its frames and closes the channel`() = runTest {
        val channel = FakeChannel(chunkedStream(listOf("a".toByteArray(), "b".toByteArray()), "{}"), "")
        val got = SSHAgentTransport(FakeFactory(channel))
            .serverStream("/gryonixnexusd.v1.Install/WatchInstall", ByteArray(0)).toList()

        assertEquals(2, got.size)
        assertTrue(channel.closed)
    }

    // ------------------------------------------------- Which device is calling

    @Test
    fun `the device id is sent on a unary call`() = runTest {
        val channel = FakeChannel(okResponse(byteArrayOf(1, 2)), "")
        val transport = SSHAgentTransport(FakeFactory(channel), deviceUID = "phone-a")
        transport.unary("/gryonixnexusd.v1.Control/GetState", ByteArray(0))
        val head = channel.written.first().decodeToString()
        assertTrue(head.contains("X-Gryonix-Device: phone-a"), head)
    }

    @Test
    fun `the device id is sent on a stream`() = runTest {
        val channel = FakeChannel(chunkedStream(listOf(byteArrayOf(7)), "{}"), "")
        val transport = SSHAgentTransport(FakeFactory(channel), deviceUID = "phone-a")
        transport.serverStream("/gryonixnexusd.v1.Control/HostMetrics", ByteArray(0)).toList()
        val head = channel.written.first().decodeToString()
        assertTrue(head.contains("X-Gryonix-Device: phone-a"), head)
    }

    @Test
    fun `no id sends no header`() = runTest {
        val channel = FakeChannel(okResponse(byteArrayOf(1)), "")
        val transport = SSHAgentTransport(FakeFactory(channel))
        transport.unary("/gryonixnexusd.v1.Control/GetState", ByteArray(0))
        val head = channel.written.first().decodeToString()
        assertTrue(!head.contains("X-Gryonix-Device"), head)
    }
}
