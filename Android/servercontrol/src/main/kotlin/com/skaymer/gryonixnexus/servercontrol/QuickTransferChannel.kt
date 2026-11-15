package com.skaymer.gryonixnexus.servercontrol

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.zip.Deflater
import java.util.zip.Inflater
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlinx.coroutines.channels.Channel
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** Why a transfer stopped */
sealed class QuickTransferFailure(message: String) : Exception(message) {
    class NotOurs : QuickTransferFailure("not this transfer")

    class Declined : QuickTransferFailure("declined")

    class Unexpected : QuickTransferFailure("unexpected message")

    class TooLarge : QuickTransferFailure("frame too large")

    class Closed : QuickTransferFailure("link closed")

    class TimedOut : QuickTransferFailure("timed out")
}

/** Seals transfer frames with the key from the QR code */
class QuickTransferCipher(private val key: ByteArray) {
    enum class Direction(val byte: Byte) { TO_SENDER(1), TO_RECEIVER(2) }

    fun seal(
        plain: ByteArray,
        direction: Direction,
        sequence: Long,
        nonce: ByteArray = TransferSeal.randomBytes(NONCE_LENGTH),
    ): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        cipher.updateAAD(header(direction, sequence))
        return nonce + cipher.doFinal(plain)
    }

    fun open(sealed: ByteArray, direction: Direction, sequence: Long): ByteArray {
        if (sealed.size < NONCE_LENGTH + 16) throw QuickTransferFailure.NotOurs()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, sealed, 0, NONCE_LENGTH))
        cipher.updateAAD(header(direction, sequence))
        return try {
            cipher.doFinal(sealed, NONCE_LENGTH, sealed.size - NONCE_LENGTH)
        } catch (_: AEADBadTagException) {
            throw QuickTransferFailure.NotOurs()
        }
    }

    /** Four digits both screens show for the same hello */
    fun code(nonce: ByteArray): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        val digest = mac.doFinal("code".toByteArray() + nonce)
        val number = ByteBuffer.wrap(digest, 0, 4).int.toLong() and 0xffffffffL
        return "%04d".format(number % 10_000)
    }

    private fun header(direction: Direction, sequence: Long): ByteArray =
        QuickTransferTicket.PREFIX.toByteArray() + direction.byte + ByteBuffer.allocate(8).putLong(sequence).array()

    companion object {
        const val NONCE_LENGTH = 12
    }
}

/** One message of the transfer conversation */
@Serializable
data class QuickTransferMessage(
    val kind: String,
    val device: String? = null,
    val nonce: String? = null,
    val servers: List<String>? = null,
    val imported: Int? = null,
) {
    companion object {
        const val HELLO = "hello"
        const val ACCEPT = "accept"
        const val DECLINE = "decline"
        const val SERVERS = "servers"
        const val DONE = "done"
    }
}

/** A byte pipe carrying one payload at a time */
interface QuickTransferLink {
    suspend fun send(payload: ByteArray)

    suspend fun receive(): ByteArray

    fun close()
}

/** Length-prefixed payloads over a byte stream */
class QuickTransferFrames {
    private var buffer = ByteArray(0)

    /** Adds received bytes, returns every payload now complete */
    fun append(bytes: ByteArray): List<ByteArray> {
        buffer += bytes
        val payloads = mutableListOf<ByteArray>()
        while (buffer.size >= 4) {
            val length = ByteBuffer.wrap(buffer, 0, 4).int.toLong() and 0xffffffffL
            if (length > MAXIMUM) throw QuickTransferFailure.TooLarge()
            if (buffer.size < 4 + length) break
            payloads += buffer.copyOfRange(4, 4 + length.toInt())
            buffer = buffer.copyOfRange(4 + length.toInt(), buffer.size)
        }
        return payloads
    }

    companion object {
        const val MAXIMUM = 8 shl 20

        fun frame(payload: ByteArray): ByteArray = ByteBuffer.allocate(4).putInt(payload.size).array() + payload
    }
}

/** Reassembles payloads that arrive in pieces */
class QuickTransferInbound {
    private val frames = QuickTransferFrames()
    private val payloads = Channel<ByteArray>(Channel.UNLIMITED)

    fun append(bytes: ByteArray) = synchronized(frames) {
        runCatching { frames.append(bytes).forEach { payloads.trySend(it) } }
            .onFailure { payloads.close(it) }
    }

    fun finish() {
        payloads.close()
    }

    suspend fun next(): ByteArray = payloads.receiveCatching().getOrNull() ?: throw QuickTransferFailure.Closed()

    companion object {
        fun chunks(data: ByteArray, size: Int): List<ByteArray> =
            (data.indices step size).map { data.copyOfRange(it, minOf(it + size, data.size)) }
    }
}

/** Encrypted, compressed messages over a link */
class QuickTransferChannel(val link: QuickTransferLink, key: ByteArray, private val role: Role) {
    enum class Role { SENDER, RECEIVER }

    private val cipher = QuickTransferCipher(key)
    private var sent = 0L
    private var received = 0L

    suspend fun send(message: QuickTransferMessage) {
        val plain = QuickTransferDeflate.compress(json.encodeToString(QuickTransferMessage.serializer(), message).toByteArray())
        val direction = if (role == Role.SENDER) QuickTransferCipher.Direction.TO_RECEIVER else QuickTransferCipher.Direction.TO_SENDER
        val sealed = cipher.seal(plain, direction, sent++)
        link.send(sealed)
    }

    suspend fun receive(): QuickTransferMessage {
        val sealed = link.receive()
        val direction = if (role == Role.SENDER) QuickTransferCipher.Direction.TO_SENDER else QuickTransferCipher.Direction.TO_RECEIVER
        val plain = cipher.open(sealed, direction, received++)
        return runCatching {
            json.decodeFromString(QuickTransferMessage.serializer(), QuickTransferDeflate.decompress(plain).decodeToString())
        }.getOrElse { throw QuickTransferFailure.Unexpected() }
    }

    fun code(nonce: ByteArray): String = cipher.code(nonce)

    fun close() = link.close()

    private companion object {
        val json = Json { ignoreUnknownKeys = true; explicitNulls = false }
    }
}

/** Raw DEFLATE, the same bytes zlib writes without a header */
object QuickTransferDeflate {
    fun compress(data: ByteArray): ByteArray {
        val deflater = Deflater(Deflater.DEFAULT_COMPRESSION, true)
        deflater.setInput(data)
        deflater.finish()
        return drain { deflater.deflate(it) }.also { deflater.end() }
    }

    fun decompress(data: ByteArray): ByteArray {
        val inflater = Inflater(true)
        inflater.setInput(data + 0)
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (!inflater.finished()) {
            val count = inflater.inflate(buffer)
            if (count == 0 && (inflater.needsInput() || inflater.needsDictionary())) break
            out.write(buffer, 0, count)
            if (out.size() > QuickTransferFrames.MAXIMUM * 4) throw QuickTransferFailure.TooLarge()
        }
        inflater.end()
        return out.toByteArray()
    }

    private fun drain(step: (ByteArray) -> Int): ByteArray {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val count = step(buffer)
            if (count == 0) break
            out.write(buffer, 0, count)
        }
        return out.toByteArray()
    }
}
