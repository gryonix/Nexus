package com.skaymer.gryonixnexus.servercontrol

import java.security.SecureRandom
import java.util.Base64
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** Passphrase encryption for exported server files */
object TransferSeal {
    const val TYPE = "gryonixserver-sealed"
    const val ITERATIONS = 600_000

    class WrongPassphrase : Exception("wrong passphrase")

    class Unreadable : Exception("not a sealed server file")

    @Serializable
    private data class Envelope(
        val ciphertext: String,
        val iterations: Int,
        val kdf: String,
        val nonce: String,
        val salt: String,
        val type: String,
        val version: Int,
    )

    private val json = Json { ignoreUnknownKeys = true }

    /** True when the file is a sealed export */
    fun isSealed(data: ByteArray): Boolean =
        runCatching { json.decodeFromString<Envelope>(data.decodeToString()).type == TYPE }.getOrDefault(false)

    fun seal(
        plain: ByteArray,
        passphrase: String,
        salt: ByteArray = randomBytes(16),
        nonce: ByteArray = randomBytes(12),
    ): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key(passphrase, salt, ITERATIONS), GCMParameterSpec(128, nonce))
        val envelope = Envelope(
            ciphertext = encode(cipher.doFinal(plain)),
            iterations = ITERATIONS,
            kdf = "pbkdf2-sha256",
            nonce = encode(nonce),
            salt = encode(salt),
            type = TYPE,
            version = 1,
        )
        return json.encodeToString(Envelope.serializer(), envelope).toByteArray()
    }

    fun open(sealed: ByteArray, passphrase: String): ByteArray {
        val envelope = runCatching { json.decodeFromString<Envelope>(sealed.decodeToString()) }.getOrNull()
            ?.takeIf { it.type == TYPE && it.kdf == "pbkdf2-sha256" && it.iterations in 1..10_000_000 }
            ?: throw Unreadable()
        val decoder = Base64.getDecoder()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            key(passphrase, decoder.decode(envelope.salt), envelope.iterations),
            GCMParameterSpec(128, decoder.decode(envelope.nonce)),
        )
        return try {
            cipher.doFinal(decoder.decode(envelope.ciphertext))
        } catch (_: AEADBadTagException) {
            throw WrongPassphrase()
        }
    }

    private fun key(passphrase: String, salt: ByteArray, iterations: Int): SecretKeySpec {
        val spec = PBEKeySpec(passphrase.toCharArray(), salt, iterations, 256)
        val bytes = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
        return SecretKeySpec(bytes, "AES")
    }

    private fun encode(bytes: ByteArray): String = Base64.getEncoder().encodeToString(bytes)

    private fun randomBytes(count: Int): ByteArray = ByteArray(count).also { SecureRandom().nextBytes(it) }
}
