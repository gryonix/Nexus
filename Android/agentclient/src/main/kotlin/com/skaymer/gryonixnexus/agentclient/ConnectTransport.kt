package com.skaymer.gryonixnexus.agentclient

import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive

/** How long a unary call may stay silent */
private const val UNARY_DEADLINE_MS = 300_000L

/** Speaks Connect-RPC over HTTP/1.1 on top of an [AgentByteStream] */
class ConnectTransport(
    private val factory: AgentStreamFactory,
    private val deviceUID: String = "",
) : AgentTransport {
    override suspend fun unary(path: String, request: ByteArray): ByteArray = coroutineScope {
        val stream = factory.open()
        var expired = false
        val watchdog = launch {
            delay(UNARY_DEADLINE_MS)
            expired = true
            stream.close()
        }
        try {
            stream.write(HTTPWire.request(path, "application/proto", request, deviceUID))
            val reader = ByteReader(stream)
            val head = HTTPWire.readHead(reader)
            val body = HTTPWire.readBody(reader, head)
            stream.close()
            if (head.status != 200) throw parseConnectError(body, head.status)
            body
        } catch (error: Throwable) {
            stream.close()
            if (expired) throw AgentError.Transport("The server did not answer in time.")
            throw error
        } finally {
            watchdog.cancel()
        }
    }

    override fun serverStream(path: String, request: ByteArray): Flow<ByteArray> = flow {
        val stream = factory.open()
        try {
            // A server-streaming request is exactly one enveloped message.
            val enveloped = ConnectEnvelope.encode(request)
            stream.write(HTTPWire.request(path, "application/connect+proto", enveloped, deviceUID))
            val reader = ByteReader(stream)
            val head = HTTPWire.readHead(reader)
            if (head.status != 200) {
                throw parseConnectError(HTTPWire.readBody(reader, head), head.status)
            }
            val decoder = ConnectEnvelope.Decoder()
            var ended = false
            HTTPWire.readChunks(reader, head) { chunk ->
                decoder.append(chunk)
                var keepGoing = true
                while (keepGoing) {
                    val frame = decoder.next() ?: break
                    if (frame.isEndOfStream) {
                        parseConnectTrailer(frame.payload)?.let { throw it }
                        ended = true
                        keepGoing = false // clean end-of-stream
                    } else {
                        emit(frame.payload)
                    }
                }
                keepGoing
            }
            if (!ended) throw AgentError.Transport(ConnectEnvelope.CUT_OFF_MESSAGE)
        } finally {
            stream.close()
        }
    }
}

// MARK: - Connect error decoding

/** A refused unary call */
fun parseConnectError(body: ByteArray, status: Int): AgentError {
    val text = body.decodeToString()
    val code = jsonField(text, "code")
    return if (code.isNullOrEmpty()) {
        AgentError.Rpc("http_$status", text)
    } else {
        AgentError.Rpc(code, jsonField(text, "message").orEmpty())
    }
}

private fun jsonField(text: String, name: String): String? = try {
    (Json.parseToJsonElement(text) as? JsonObject)?.get(name)?.jsonPrimitive?.content
} catch (_: Throwable) {
    null
}

/** An end-of-stream envelope is JSON: `{}` on success, or `{"error": {...}}` */
fun parseConnectTrailer(payload: ByteArray): AgentError? {
    if (payload.isEmpty()) return null
    return try {
        val root = Json.parseToJsonElement(payload.decodeToString()) as? JsonObject ?: return null
        val error = root["error"] as? JsonObject ?: return null
        AgentError.Rpc(
            error["code"]?.jsonPrimitive?.content?.ifEmpty { "unknown" } ?: "unknown",
            error["message"]?.jsonPrimitive?.content.orEmpty(),
        )
    } catch (_: Throwable) {
        null
    }
}

// MARK: - Buffered reader

/** Buffers an [AgentByteStream] into line/count/chunk reads for HTTP parsing */
class ByteReader(private val stream: AgentByteStream) {
    private var buffer = ByteArray(0)
    private var eof = false

    private suspend fun fill() {
        if (eof) return
        val chunk = stream.read()
        if (chunk.isEmpty()) eof = true else buffer += chunk
    }

    suspend fun readLine(): String {
        while (true) {
            val at = indexOfCRLF()
            if (at >= 0) {
                val line = buffer.copyOfRange(0, at).decodeToString()
                buffer = buffer.copyOfRange(at + 2, buffer.size)
                return line
            }
            if (eof) {
                val line = buffer.decodeToString()
                buffer = ByteArray(0)
                return line
            }
            fill()
        }
    }

    private fun indexOfCRLF(): Int {
        for (i in 0 until buffer.size - 1) {
            if (buffer[i] == 0x0d.toByte() && buffer[i + 1] == 0x0a.toByte()) return i
        }
        return -1
    }

    suspend fun read(count: Int): ByteArray {
        while (buffer.size < count && !eof) fill()
        val n = minOf(count, buffer.size)
        val out = buffer.copyOfRange(0, n)
        buffer = buffer.copyOfRange(n, buffer.size)
        return out
    }

    suspend fun readAll(): ByteArray {
        while (!eof) fill()
        val out = buffer
        buffer = ByteArray(0)
        return out
    }
}

// MARK: - HTTP/1.1 framing

object HTTPWire {
    data class Head(val status: Int, val chunked: Boolean, val contentLength: Int?)

    fun request(
        path: String,
        contentType: String,
        body: ByteArray,
        deviceUID: String = "",
    ): ByteArray {
        val head = buildString {
            append("POST $path HTTP/1.1\r\n")
            append("Host: localhost\r\n")
            append("Content-Type: $contentType\r\n")
            append("Content-Length: ${body.size}\r\n")
            if (deviceUID.isNotEmpty()) append("$DEVICE_HEADER: $deviceUID\r\n")
            append("Connection: close\r\n\r\n")
        }
        return head.toByteArray() + body
    }

    const val DEVICE_HEADER = "X-Gryonix-Device"

    suspend fun readHead(reader: ByteReader): Head {
        val statusLine = reader.readLine()
        val parts = statusLine.split(" ", limit = 3)
        val status = parts.getOrNull(1)?.toIntOrNull()
        if (parts.size < 2 || status == null) {
            throw AgentError.Transport("bad status line: $statusLine")
        }
        var chunked = false
        var contentLength: Int? = null
        while (true) {
            val line = reader.readLine()
            if (line.isEmpty()) break
            val lower = line.lowercase()
            if (lower.startsWith("transfer-encoding:") && lower.contains("chunked")) {
                chunked = true
            } else if (lower.startsWith("content-length:")) {
                contentLength = line.drop("content-length:".length).trim().toIntOrNull()
            }
        }
        return Head(status, chunked, contentLength)
    }

    /** The full body of a non-streaming response */
    suspend fun readBody(reader: ByteReader, head: Head): ByteArray {
        if (head.chunked) {
            var out = ByteArray(0)
            readChunks(reader, head) { out += it; true }
            return out
        }
        head.contentLength?.let { return reader.read(it) }
        return reader.readAll()
    }

    /** Feed each body chunk to [onChunk] as it arrives */
    suspend fun readChunks(reader: ByteReader, head: Head, onChunk: suspend (ByteArray) -> Boolean) {
        if (!head.chunked) {
            val body = head.contentLength?.let { reader.read(it) } ?: reader.readAll()
            onChunk(body)
            return
        }
        while (true) {
            val sizeLine = reader.readLine()
            val hex = sizeLine.substringBefore(';').trim()
            val size = hex.toIntOrNull(16)
                ?: throw AgentError.Transport("bad chunk size: $sizeLine")
            if (size == 0) {
                reader.readLine() // final CRLF after the terminator
                return
            }
            val chunk = reader.read(size)
            reader.readLine() // CRLF after each chunk
            if (!onChunk(chunk)) return
        }
    }
}
