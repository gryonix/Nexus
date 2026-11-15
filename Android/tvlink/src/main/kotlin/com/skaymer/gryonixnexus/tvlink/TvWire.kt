package com.skaymer.gryonixnexus.tvlink

import java.io.ByteArrayOutputStream
import java.util.Base64
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

object TvLinkService {
    /** NSD's spelling of the Bonjour type: with the trailing dot. */
    const val NSD_TYPE = "_gryonixnexus-tv._tcp."
    const val PROTOCOL_VERSION = 1
    const val ID_KEY = "id"
    /** When the TV app last said it is on screen. */
    const val AWAKE_KEY = "at"
    const val AWAKE_FRESHNESS_SECONDS = 180L
    const val PREFERRED_PORT = 47390
    const val LINK_SCHEME = "gryonixnexus"
    const val LINK_HOST = "tv"
}

/** Length-prefixed frames: 4-byte big-endian length, then the payload. */
object TvFrame {
    const val MAX_LENGTH = 8 shl 20

    fun encode(payload: ByteArray): ByteArray {
        val out = ByteArrayOutputStream(payload.size + 4)
        val n = payload.size
        out.write(byteArrayOf((n ushr 24).toByte(), (n ushr 16).toByte(), (n ushr 8).toByte(), n.toByte()))
        out.write(payload)
        return out.toByteArray()
    }

    /** Pulls whole frames out of bytes arriving in pieces. */
    class Reader {
        private var buffer = ByteArray(0)

        fun append(bytes: ByteArray) {
            buffer += bytes
        }

        fun next(): ByteArray? {
            if (buffer.size < 4) return null
            val length = buffer.take(4).fold(0) { acc, b -> (acc shl 8) or (b.toInt() and 0xFF) }
            if (length < 0 || length > MAX_LENGTH) throw TvLinkException.TooLarge(length)
            if (buffer.size < 4 + length) return null
            val payload = buffer.copyOfRange(4, 4 + length)
            buffer = buffer.copyOfRange(4 + length, buffer.size)
            return payload
        }
    }
}

internal val TvJson = Json {
    explicitNulls = false
    encodeDefaults = true
    ignoreUnknownKeys = true
}

internal fun ByteArray.b64(): String = Base64.getEncoder().encodeToString(this)
internal fun String.unb64(): ByteArray = Base64.getDecoder().decode(this)

/** The plaintext messages of the handshake. Binary fields are base64. */
@Serializable
data class TvHandshakeMessage(
    val code: String? = null,
    val id: String? = null,
    val key: String? = null,
    val mode: String? = null,
    val name: String? = null,
    val nonce: String? = null,
    val round: Int? = null,
    val t: String,
    val v: Int? = null,
    val value: String? = null,
) {
    fun encoded(): ByteArray = TvJson.encodeToString(serializer(), this).toByteArray()

    companion object {
        const val HELLO = "hello"
        const val COMMIT = "commit"
        const val REVEAL = "reveal"
        const val ERROR = "error"

        fun decode(bytes: ByteArray): TvHandshakeMessage = TvJson.decodeFromString(serializer(), bytes.decodeToString())
    }
}

/** Why a TV refused, as both platforms spell it. */
enum class TvRefusal(val wire: String) {
    WRONG_CODE("wrong-code"),
    BUSY("busy"),
    UNKNOWN_PHONE("unknown-phone"),
    VERSION("version"),
    PROTOCOL("protocol");

    companion object {
        fun of(wire: String?): TvRefusal = entries.firstOrNull { it.wire == wire } ?: PROTOCOL
    }
}

@Serializable
data class TvSentServer(
    val id: String,
    val name: String,
    val transfer: String? = null,
)

/** What a phone says about its license. */
@Serializable
data class TvLicenceVouch(
    val active: Boolean,
    val device: String? = null,
    val expires: Long? = null,
    val plan: String? = null,
    val token: String? = null,
)

/** A sealed request or answer. */
@Serializable
data class TvMessage(
    val code: String? = null,
    val items: List<TvSentServer>? = null,
    val licence: TvLicenceVouch? = null,
    val t: String,
) {
    fun encoded(): ByteArray = TvJson.encodeToString(serializer(), this).toByteArray()

    companion object {
        const val LIST = "list"
        const val PUT = "put"
        const val LICENCE = "licence"
        const val UNPAIR = "unpair"
        const val PAIRED = "paired"
        const val SERVERS = "servers"
        const val OK = "ok"
        const val ERROR = "error"

        fun decode(bytes: ByteArray): TvMessage = TvJson.decodeFromString(serializer(), bytes.decodeToString())
    }
}

/** Who is on one end of the link. */
@Serializable
data class TvPeer(
    @SerialName("id") val id: String,
    @SerialName("name") val name: String,
)

sealed class TvLinkException(message: String) : Exception(message) {
    class Refused(val reason: TvRefusal) : TvLinkException("refused: ${reason.wire}")
    class CodeMismatch : TvLinkException("code mismatch")
    class Unexpected(what: String) : TvLinkException("unexpected: $what")
    class WrongPeer : TvLinkException("another TV answered")
    class TooLarge(length: Int) : TvLinkException("frame of $length bytes")
    class CannotOpen : TvLinkException("a sealed frame did not open")
    class Closed : TvLinkException("connection closed")
}
