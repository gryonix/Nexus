package com.skaymer.gryonixnexus.agentclient

import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class ConnectTransportTest {
    private class ScriptedStream(response: ByteArray, private val chunkSize: Int) : AgentByteStream {
        private var remaining = response
        val written = mutableListOf<ByteArray>()
        var closed = false

        override suspend fun write(data: ByteArray) {
            written += data
        }

        override suspend fun read(): ByteArray {
            if (remaining.isEmpty()) return ByteArray(0)
            val n = minOf(chunkSize, remaining.size)
            val out = remaining.copyOfRange(0, n)
            remaining = remaining.copyOfRange(n, remaining.size)
            return out
        }

        override suspend fun close() {
            closed = true
        }
    }

    private class OneShotFactory(val stream: ScriptedStream) : AgentStreamFactory {
        override suspend fun open(): AgentByteStream = stream
    }

    private fun streamingResponse(frames: List<ByteArray>, trailer: String): ByteArray {
        val body = frames.fold(ByteArray(0)) { acc, f -> acc + ConnectEnvelope.encode(f) } +
            ConnectEnvelope.encode(trailer.toByteArray(), ConnectEnvelope.END_OF_STREAM_FLAG)
        val head = "HTTP/1.1 200 OK\r\nContent-Type: application/connect+proto\r\n" +
            "Transfer-Encoding: chunked\r\n\r\n"
        val chunk = body.size.toString(16) + "\r\n"
        return head.toByteArray() + chunk.toByteArray() + body + "\r\n0\r\n\r\n".toByteArray()
    }

    @Test
    fun `a unary call sends a POST and returns the body`() = runTest {
        val body = byteArrayOf(1, 2, 3, 4)
        val response = ("HTTP/1.1 200 OK\r\nContent-Length: ${body.size}\r\n\r\n").toByteArray() + body
        val stream = ScriptedStream(response, chunkSize = 5)
        val transport = ConnectTransport(OneShotFactory(stream))

        val out = transport.unary("/gryonixnexusd.v1.Install/ProvisionHost", byteArrayOf(9))

        assertContentEquals(body, out)
        val request = stream.written.single().decodeToString()
        assertTrue(request.startsWith("POST /gryonixnexusd.v1.Install/ProvisionHost HTTP/1.1\r\n"))
        assertTrue(request.contains("Content-Type: application/proto\r\n"))
        assertTrue(request.contains("Connection: close\r\n"))
        assertTrue(stream.closed, "every RPC owns its connection and must close it")
    }

    @Test
    fun `a refused unary call keeps the connect code`() = runTest {
        val body = """{"code":"already_exists","message":"this host is already installing this service (job 7)"}"""
        val response = ("HTTP/1.1 409 Conflict\r\nContent-Length: ${body.length}\r\n\r\n" + body).toByteArray()
        val transport = ConnectTransport(OneShotFactory(ScriptedStream(response, chunkSize = 11)))

        val error = assertFailsWith<AgentError.Rpc> {
            transport.unary("/gryonixnexusd.v1.Install/InstallService", ByteArray(0))
        }
        assertEquals("already_exists", error.code)
        assertTrue(error.text.contains("already installing"))
    }

    @Test
    fun `a body that is not a connect error still reports a refusal`() = runTest {
        val body = "404 page not found"
        val response = ("HTTP/1.1 404 Not Found\r\nContent-Length: ${body.length}\r\n\r\n" + body).toByteArray()
        val transport = ConnectTransport(OneShotFactory(ScriptedStream(response, chunkSize = 3)))

        val error = assertFailsWith<AgentError.Rpc> {
            transport.unary("/gryonixnexusd.v1.Install/WatchInstall", ByteArray(0))
        }
        assertEquals("http_404", error.code, "a dead route must read as a refusal, not as a decode failure")
    }

    @Test
    fun `a stream yields every frame and ends on a clean trailer`() = runTest {
        val frames = listOf("started".toByteArray(), "pulling".toByteArray(), "done".toByteArray())
        val stream = ScriptedStream(streamingResponse(frames, "{}"), chunkSize = 3)
        val transport = ConnectTransport(OneShotFactory(stream))

        val got = transport.serverStream("/gryonixnexusd.v1.Install/WatchInstall", ByteArray(0)).toList()

        assertEquals(3, got.size)
        assertContentEquals("started".toByteArray(), got[0])
        assertContentEquals("done".toByteArray(), got[2])
        assertTrue(stream.closed)
    }

    @Test
    fun `a trailer carrying an error fails the stream, after the frames before it`() = runTest {
        val body = streamingResponse(
            listOf("creating directories".toByteArray(), "docker: port is allocated".toByteArray()),
            """{"error":{"code":"internal","message":"port 53 is already allocated"}}""",
        )
        val transport = ConnectTransport(OneShotFactory(ScriptedStream(body, chunkSize = 4)))

        val seen = mutableListOf<ByteArray>()
        val error = assertFailsWith<AgentError.Rpc> {
            transport.serverStream("/gryonixnexusd.v1.Install/InstallService", ByteArray(0))
                .collect { seen += it }
        }
        assertEquals("internal", error.code)
        assertEquals("port 53 is already allocated", error.text)
        assertEquals(2, seen.size, "the lines before the failure are still the operator's answer")
    }

    @Test
    fun `a stream that ends without the end-of-stream frame is a cut connection`() = runTest {
        val body = ConnectEnvelope.encode("half way".toByteArray())
        val head = "HTTP/1.1 200 OK\r\nContent-Type: application/connect+proto\r\n" +
            "Transfer-Encoding: chunked\r\n\r\n"
        val response = head.toByteArray() + (body.size.toString(16) + "\r\n").toByteArray() + body +
            "\r\n0\r\n\r\n".toByteArray()
        val transport = ConnectTransport(OneShotFactory(ScriptedStream(response, chunkSize = 7)))

        val error = assertFailsWith<AgentError.Transport> {
            transport.serverStream("/gryonixnexusd.v1.Install/InstallService", ByteArray(0)).toList()
        }
        assertEquals(ConnectEnvelope.CUT_OFF_MESSAGE, error.detail)
    }

    @Test
    fun `a streaming request is sent as a single envelope`() = runTest {
        val stream = ScriptedStream(streamingResponse(listOf("x".toByteArray()), "{}"), chunkSize = 64)
        val transport = ConnectTransport(OneShotFactory(stream))

        transport.serverStream("/gryonixnexusd.v1.Install/WatchInstall", byteArrayOf(7, 7, 7)).toList()

        val sent = stream.written.single()
        val bodyStart = sent.decodeToString().indexOf("\r\n\r\n") + 4
        val body = sent.copyOfRange(bodyStart, sent.size)
        assertContentEquals(ConnectEnvelope.encode(byteArrayOf(7, 7, 7)), body)
        assertTrue(sent.decodeToString().contains("Content-Type: application/connect+proto"))
    }

    @Test
    fun `the device header is sent when this installation has an id`() {
        val text = HTTPWire.request("/x", "application/proto", ByteArray(0), deviceUID = "dev-42")
            .decodeToString()
        assertTrue(text.contains("${HTTPWire.DEVICE_HEADER}: dev-42\r\n"), text)
    }

    /** NEGATIVE CONTROL */
    @Test
    fun `no header at all is sent when there is no id`() {
        val text = HTTPWire.request("/x", "application/proto", ByteArray(0)).decodeToString()
        assertFalse(text.contains(HTTPWire.DEVICE_HEADER), text)
    }

    @Test
    fun `the streaming request carries it as well`() {
        val text = HTTPWire.request("/x", "application/connect+proto", ByteArray(0), deviceUID = "dev-42")
            .decodeToString()
        assertTrue(text.contains("${HTTPWire.DEVICE_HEADER}: dev-42"), text)
    }

    @Test
    fun `the header does not displace Content-Length`() {
        val body = "hello".encodeToByteArray()
        val text = HTTPWire.request("/x", "application/proto", body, deviceUID = "dev-42").decodeToString()
        assertTrue(text.contains("Content-Length: ${body.size}\r\n"), text)
        assertTrue(text.substringBefore("\r\n\r\n").endsWith("Connection: close"), text)
    }
}
