package com.skaymer.gryonixnexus.recipe

import java.security.SecureRandom
import java.util.Base64
import org.bouncycastle.crypto.agreement.X25519Agreement
import org.bouncycastle.crypto.params.X25519PrivateKeyParameters
import org.bouncycastle.crypto.params.X25519PublicKeyParameters

data class WireGuardKeyPair(val privateKey: String, val publicKey: String)

enum class WireGuardKeySlot { VPS, HOME }

/** Whoever mints the tunnel keys */
fun interface WireGuardKeyProvider {
    fun makeKeyPair(slot: WireGuardKeySlot): WireGuardKeyPair
}

internal object Curve25519 {
    /** The public key for [privateKey], i.e */
    fun publicKey(privateKey: ByteArray): ByteArray = X25519PrivateKeyParameters(privateKey, 0).generatePublicKey().encoded

    fun scalarMultiply(scalar: ByteArray, uCoordinate: ByteArray): ByteArray {
        require(scalar.size == 32) { "a scalar is 32 bytes, got ${scalar.size}" }
        require(uCoordinate.size == 32) { "a u-coordinate is 32 bytes, got ${uCoordinate.size}" }
        val agreement = X25519Agreement().apply { init(X25519PrivateKeyParameters(scalar, 0)) }
        return ByteArray(agreement.agreementSize).also {
            agreement.calculateAgreement(X25519PublicKeyParameters(uCoordinate, 0), it, 0)
        }
    }
}

class SecureRandomWireGuardKeyProvider(
    private val random: SecureRandom = SecureRandom()
) : WireGuardKeyProvider {
    override fun makeKeyPair(slot: WireGuardKeySlot): WireGuardKeyPair {
        val privateKey = ByteArray(32).also(random::nextBytes)
        privateKey[0] = (privateKey[0].toInt() and 248).toByte()
        privateKey[31] = (privateKey[31].toInt() and 127 or 64).toByte()
        val encoder = Base64.getEncoder()
        return WireGuardKeyPair(
            privateKey = encoder.encodeToString(privateKey),
            publicKey = encoder.encodeToString(Curve25519.publicKey(privateKey))
        )
    }
}
