package com.skaymer.gryonixnexus.tvlink

import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException
import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable

/** Where a phone reaches a TV. */
@Serializable
data class TvAddress(val host: String, val port: Int = TvLinkService.PREFERRED_PORT) {
    companion object {
        fun parse(text: String): TvAddress? {
            val trimmed = text.trim()
            if (trimmed.isEmpty() || trimmed.contains(' ')) return null
            if (trimmed.startsWith("[")) {
                val close = trimmed.indexOf(']')
                if (close < 0) return null
                val host = trimmed.substring(1, close)
                val rest = trimmed.substring(close + 1)
                if (rest.isEmpty()) return TvAddress(host)
                val port = rest.removePrefix(":").toIntOrNull()?.takeIf { rest.startsWith(":") && it in 1..65535 }
                return port?.let { TvAddress(host, it) }
            }
            val parts = trimmed.split(":")
            return when (parts.size) {
                1 -> TvAddress(trimmed)
                2 -> {
                    val port = parts[1].toIntOrNull()?.takeIf { it in 1..65535 }
                    if (parts[0].isEmpty() || port == null) null else TvAddress(parts[0], port)
                }
                else -> TvAddress(trimmed)
            }
        }
    }
}

/** What a TV's QR code says: `gryonixnexus://tv?host=…&port=…&code=…&name=…`. */
data class TvPairingLink(val address: TvAddress, val code: TvPairingCode, val name: String?) {
    companion object {
        fun parse(text: String): TvPairingLink? {
            val uri = runCatching { URI(text.trim()) }.getOrNull() ?: return null
            if (uri.scheme != TvLinkService.LINK_SCHEME || uri.host != TvLinkService.LINK_HOST) return null
            val query = (uri.rawQuery ?: return null).split("&").mapNotNull {
                val pair = it.split("=", limit = 2)
                if (pair.size == 2) URLDecoder.decode(pair[0], "UTF-8") to URLDecoder.decode(pair[1], "UTF-8") else null
            }.toMap()
            val host = query["host"]?.takeIf { it.isNotEmpty() } ?: return null
            val code = query["code"]?.let(TvPairingCode::parse) ?: return null
            val port = query["port"]?.toIntOrNull() ?: TvLinkService.PREFERRED_PORT
            return TvPairingLink(TvAddress(host, port), code, query["name"])
        }

        fun format(link: TvPairingLink): String =
            "${TvLinkService.LINK_SCHEME}://${TvLinkService.LINK_HOST}?host=${enc(link.address.host)}" +
                "&port=${link.address.port}&code=${link.code.digits}" + (link.name?.let { "&name=${enc(it)}" } ?: "")

        private fun enc(text: String) = URLEncoder.encode(text, "UTF-8").replace("+", "%20")
    }
}

/** One TCP connection speaking frames; blocking, so used on [Dispatchers.IO]. */
class TvConnection(private val socket: Socket) : AutoCloseable {
    private val input: InputStream = socket.getInputStream()
    private val output: OutputStream = socket.getOutputStream()
    private val reader = TvFrame.Reader()

    fun send(payload: ByteArray) {
        output.write(TvFrame.encode(payload))
        output.flush()
    }

    fun send(message: TvHandshakeMessage) = send(message.encoded())

    fun receive(timeoutMillis: Int = 20_000): ByteArray {
        socket.soTimeout = timeoutMillis
        val chunk = ByteArray(64 * 1024)
        while (true) {
            reader.next()?.let { return it }
            val count = try {
                input.read(chunk)
            } catch (_: SocketTimeoutException) {
                throw TvLinkException.Closed()
            }
            if (count < 0) throw TvLinkException.Closed()
            reader.append(chunk.copyOf(count))
        }
    }

    fun receiveHandshake(timeoutMillis: Int = 20_000) = TvHandshakeMessage.decode(receive(timeoutMillis))

    val remoteHost: String? get() = socket.inetAddress?.hostAddress

    override fun close() = runCatching { socket.close() }.let { }

    companion object {
        fun open(address: TvAddress, timeoutMillis: Int = 8_000): TvConnection {
            val socket = Socket()
            socket.tcpNoDelay = true
            socket.connect(InetSocketAddress(address.host, address.port), timeoutMillis)
            return TvConnection(socket)
        }
    }
}

/** A pairing in progress: connected, the TV shows its code. */
class TvPairingAttempt private constructor(
    private val connection: TvConnection,
    private val machine: TvPairingPhone,
    val tv: TvPeer,
    val address: TvAddress,
) {
    /** Runs the twenty rounds with the typed code. */
    suspend fun enter(code: TvPairingCode): TvPairingResult = withContext(Dispatchers.IO) {
        try {
            rounds(code)
        } finally {
            connection.close()
        }
    }

    private fun rounds(code: TvPairingCode): TvPairingResult {
        var outgoing = machine.enter(code)
        while (true) {
            connection.send(outgoing)
            when (val step = machine.receive(connection.receiveHandshake())) {
                is TvPairingPhone.Step.Send -> outgoing = step.message
                is TvPairingPhone.Step.SendSealed -> {
                    connection.send(step.frame)
                    return machine.receiveSealed(connection.receive())
                }
                TvPairingPhone.Step.NeedsCode -> throw TvLinkException.Unexpected("code asked twice")
            }
        }
    }

    fun cancel() = connection.close()

    companion object {
        suspend fun start(address: TvAddress, phone: TvPeer, random: TvLinkRandom = SystemTvLinkRandom()): TvPairingAttempt =
            withContext(Dispatchers.IO) {
                val connection = TvConnection.open(address)
                try {
                    val machine = TvPairingPhone(phone, random)
                    connection.send(machine.hello())
                    val step = machine.receive(connection.receiveHandshake())
                    val tv = machine.tv
                    if (step != TvPairingPhone.Step.NeedsCode || tv == null) throw TvLinkException.Unexpected("hello")
                    TvPairingAttempt(connection, machine, tv, TvAddress(connection.remoteHost ?: address.host, address.port))
                } catch (error: Throwable) {
                    connection.close()
                    throw error
                }
            }
    }
}

/** One session with a paired TV. */
object TvLinkClient {
    suspend fun exchange(
        requests: List<TvMessage>,
        address: TvAddress,
        phone: TvPeer,
        tvId: String,
        pairingKey: ByteArray,
        random: TvLinkRandom = SystemTvLinkRandom(),
    ): List<TvMessage> = withContext(Dispatchers.IO) {
        TvConnection.open(address).use { connection ->
            val handshake = TvSessionPhone(phone, tvId, pairingKey, random)
            connection.send(handshake.hello())
            val channel = handshake.receive(connection.receiveHandshake())
            requests.map { request ->
                connection.send(channel.seal(request))
                channel.openMessage(connection.receive())
            }
        }
    }
}
