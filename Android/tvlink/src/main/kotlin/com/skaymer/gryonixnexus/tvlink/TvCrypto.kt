package com.skaymer.gryonixnexus.tvlink

import java.math.BigInteger
import java.nio.ByteBuffer
import java.security.AlgorithmParameters
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import java.security.spec.ECPoint
import java.security.spec.ECPublicKeySpec
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class TvKeyPair(val private: PrivateKey, val publicX963: ByteArray)

interface TvLinkRandom {
    fun bytes(count: Int): ByteArray
    fun keyPair(): TvKeyPair
}

class SystemTvLinkRandom : TvLinkRandom {
    private val random = SecureRandom()

    override fun bytes(count: Int): ByteArray = ByteArray(count).also(random::nextBytes)

    override fun keyPair(): TvKeyPair {
        val generator = KeyPairGenerator.getInstance("EC")
        generator.initialize(ECGenParameterSpec("secp256r1"), random)
        val pair = generator.generateKeyPair()
        return TvKeyPair(pair.private, TvCrypto.x963(pair.public as ECPublicKey))
    }
}

/** The six digits on the TV. */
class TvPairingCode private constructor(val value: Int) {
    fun bit(round: Int): Int = (value shr round) and 1

    val digits: String get() = "%06d".format(value)

    override fun equals(other: Any?): Boolean = other is TvPairingCode && other.value == value
    override fun hashCode(): Int = value
    override fun toString(): String = digits.substring(0, 3) + " " + digits.substring(3)

    companion object {
        const val BIT_COUNT = 20

        fun of(value: Int): TvPairingCode? = if (value in 0 until 1_000_000) TvPairingCode(value) else null

        /** Digits typed with or without spaces or a dash. */
        fun parse(text: String): TvPairingCode? {
            val digits = text.filter { !it.isWhitespace() && it != '-' }
            if (digits.length != 6 || !digits.all { it in '0'..'9' }) return null
            return of(digits.toInt())
        }
    }
}

/** The primitives, the same as `TVLinkCrypto` in Swift. */
object TvCrypto {
    const val NONCE_LENGTH = 32
    const val COMMIT_NONCE_LENGTH = 16

    val p256: ECParameterSpec by lazy {
        AlgorithmParameters.getInstance("EC").apply { init(ECGenParameterSpec("secp256r1")) }
            .getParameterSpec(ECParameterSpec::class.java)
    }

    fun x963(key: ECPublicKey): ByteArray = byteArrayOf(4) + fixed(key.w.affineX) + fixed(key.w.affineY)

    fun publicKey(x963: ByteArray): ECPublicKey {
        if (x963.size != 65 || x963[0] != 4.toByte()) throw TvLinkException.Unexpected("public key")
        val point = ECPoint(BigInteger(1, x963.copyOfRange(1, 33)), BigInteger(1, x963.copyOfRange(33, 65)))
        return KeyFactory.getInstance("EC").generatePublic(ECPublicKeySpec(point, p256)) as ECPublicKey
    }

    private fun fixed(value: BigInteger): ByteArray {
        val raw = value.toByteArray().dropWhile { it == 0.toByte() }.toByteArray()
        return ByteArray(32 - raw.size) + raw
    }

    fun sharedSecret(own: PrivateKey, peer: ByteArray): ByteArray =
        KeyAgreement.getInstance("ECDH").run {
            init(own)
            doPhase(publicKey(peer), true)
            generateSecret()
        }

    fun hmac(key: ByteArray, data: ByteArray): ByteArray =
        Mac.getInstance("HmacSHA256").run {
            init(SecretKeySpec(key, "HmacSHA256"))
            doFinal(data)
        }

    fun sha256(data: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(data)

    /** HKDF-SHA256 (RFC 5869), 32 bytes. */
    fun derive(material: ByteArray, salt: ByteArray, info: String): ByteArray {
        val prk = hmac(if (salt.isEmpty()) ByteArray(32) else salt, material)
        return hmac(prk, info.toByteArray() + byteArrayOf(1))
    }

    fun commitment(round: Int, bit: Int, ownKey: ByteArray, peerKey: ByteArray, nonce: ByteArray): ByteArray =
        hmac(nonce, "gx-tv-commit".toByteArray() + byteArrayOf(round.toByte()) + ownKey + peerKey + byteArrayOf(bit.toByte()))

    fun constantTimeEquals(a: ByteArray, b: ByteArray): Boolean = MessageDigest.isEqual(a, b)
}

/** Everything said before the keys, length-prefixed and hashed. */
class TvTranscript {
    private var bytes = "gryonixnexus-tv-v1".toByteArray()

    fun append(field: ByteArray) {
        bytes += ByteBuffer.allocate(4).putInt(field.size).array() + field
    }

    fun append(text: String) = append(text.toByteArray())

    val hash: ByteArray get() = TvCrypto.sha256(bytes)
}

/** AES-256-GCM both ways, counters for nonces. */
class TvSecureChannel(private val sendKey: ByteArray, private val receiveKey: ByteArray) {
    private var sent = 0L
    private var received = 0L

    fun seal(plaintext: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(sendKey, "AES"), GCMParameterSpec(128, nonce(sent)))
        sent += 1
        return cipher.doFinal(plaintext)
    }

    fun open(sealed: ByteArray): ByteArray {
        if (sealed.size < 16) throw TvLinkException.CannotOpen()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(receiveKey, "AES"), GCMParameterSpec(128, nonce(received)))
        val plain = try {
            cipher.doFinal(sealed)
        } catch (_: Exception) {
            throw TvLinkException.CannotOpen()
        }
        received += 1
        return plain
    }

    fun seal(message: TvMessage): ByteArray = seal(message.encoded())

    fun openMessage(sealed: ByteArray): TvMessage = TvMessage.decode(open(sealed))

    private fun nonce(counter: Long): ByteArray = ByteArray(4) + ByteBuffer.allocate(8).putLong(counter).array()
}

/** The keys a finished handshake leaves. */
class TvHandshakeKeys(val phoneToTv: ByteArray, val tvToPhone: ByteArray, val pairingKey: ByteArray?) {
    val phoneChannel: TvSecureChannel get() = TvSecureChannel(phoneToTv, tvToPhone)

    companion object {
        fun derive(material: ByteArray, transcript: ByteArray, pairing: Boolean) = TvHandshakeKeys(
            TvCrypto.derive(material, transcript, "gx-tv phone->tv"),
            TvCrypto.derive(material, transcript, "gx-tv tv->phone"),
            if (pairing) TvCrypto.derive(material, transcript, "gx-tv pairing key") else null,
        )
    }
}
