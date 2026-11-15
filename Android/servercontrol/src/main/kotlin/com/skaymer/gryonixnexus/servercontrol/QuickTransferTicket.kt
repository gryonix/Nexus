package com.skaymer.gryonixnexus.servercontrol

import java.nio.ByteBuffer
import java.util.Base64
import java.util.UUID

/** What the transfer QR code carries: session, key, addresses */
data class QuickTransferTicket(
    val session: ByteArray,
    val key: ByteArray,
    val port: Int,
    val addresses: List<String>,
) {
    /** The text put into the QR code */
    val text: String
        get() = listOf(PREFIX, encode(session), encode(key), port.toString(), addresses.joinToString(","))
            .joinToString(";")

    /** Bluetooth service the sender advertises for this session */
    val bluetoothService: UUID
        get() {
            val buffer = ByteBuffer.wrap(session)
            return UUID(buffer.long, buffer.long)
        }

    override fun equals(other: Any?): Boolean =
        other is QuickTransferTicket && session.contentEquals(other.session) && key.contentEquals(other.key) &&
            port == other.port && addresses == other.addresses

    override fun hashCode(): Int = session.contentHashCode() * 31 + port

    companion object {
        const val PREFIX = "GXT1"
        const val SESSION_LENGTH = 16
        const val KEY_LENGTH = 32

        /** A new ticket with random session and key */
        fun fresh(port: Int, addresses: List<String>) = QuickTransferTicket(
            TransferSeal.randomBytes(SESSION_LENGTH), TransferSeal.randomBytes(KEY_LENGTH), port, addresses,
        )

        fun parse(text: String): QuickTransferTicket? {
            val parts = text.trim().split(";")
            if (parts.size != 5 || parts[0] != PREFIX) return null
            val session = decode(parts[1])?.takeIf { it.size == SESSION_LENGTH } ?: return null
            val key = decode(parts[2])?.takeIf { it.size == KEY_LENGTH } ?: return null
            val port = parts[3].toIntOrNull()?.takeIf { it in 0..65535 } ?: return null
            val addresses = parts[4].split(",").filter(::isAddress)
            return QuickTransferTicket(session, key, port, addresses)
        }

        fun isAddress(text: String): Boolean {
            val octets = text.split(".")
            return octets.size == 4 && octets.all { octet ->
                octet.isNotEmpty() && octet.all(Char::isDigit) && (octet.toIntOrNull() ?: 256) <= 255
            }
        }

        internal fun encode(bytes: ByteArray): String = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)

        internal fun decode(text: String): ByteArray? = runCatching { Base64.getUrlDecoder().decode(text) }.getOrNull()
    }
}
