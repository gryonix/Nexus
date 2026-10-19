package com.skaymer.gryonixnexus.app.licensing

import java.util.Base64
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer

enum class LicensePlan { MONTHLY, YEARLY, LIFETIME }

enum class LicenseProduct {
    NEXUS, VPN, BUNDLE;

    fun covers(app: LicenseProduct): Boolean = this == BUNDLE || this == app
}

/** A signed permission for one device, checked offline. */
data class LicenseToken(
    val device: String,
    val license: String,
    val plan: LicensePlan,
    val product: LicenseProduct,
    val issued: Long,
    /** Unix seconds; null for a lifetime license. */
    val expires: Long?,
)

sealed class LicenseTokenError : Exception() {
    object Malformed : LicenseTokenError() { private fun readResolve(): Any = Malformed }
    object BadSignature : LicenseTokenError() { private fun readResolve(): Any = BadSignature }
    object OtherDevice : LicenseTokenError() { private fun readResolve(): Any = OtherDevice }
    object OtherProduct : LicenseTokenError() { private fun readResolve(): Any = OtherProduct }
    data class Expired(val at: Long) : LicenseTokenError()
}

object LicenseTokens {
    /** The public half of the key gryonix.com signs with. */
    const val PRODUCTION_KEY = "Z+t5tcFWudIouFWnpjgf82+2KGtpQD7lodD0f7smoDc="

    @Serializable
    private data class Payload(
        val dev: String,
        val exp: Long? = null,
        val iat: Long,
        val lic: String,
        val plan: String,
        val prod: String,
        val v: Int,
    )

    private val json = Json { ignoreUnknownKeys = true }

    fun verify(
        text: String,
        device: String,
        now: Long,
        publicKey: String = PRODUCTION_KEY,
        app: LicenseProduct = LicenseProduct.NEXUS,
    ): LicenseToken {
        val parts = text.trim().split(".")
        if (parts.size != 2) throw LicenseTokenError.Malformed
        val data = decode(parts[0]) ?: throw LicenseTokenError.Malformed
        val signature = decode(parts[1]) ?: throw LicenseTokenError.Malformed
        if (!signatureValid(publicKey, data, signature)) throw LicenseTokenError.BadSignature
        val payload = runCatching { json.decodeFromString<Payload>(data.toString(Charsets.UTF_8)) }
            .getOrNull()?.takeIf { it.v == 1 } ?: throw LicenseTokenError.Malformed
        return token(payload, device, now, app)
    }

    private fun token(payload: Payload, device: String, now: Long, app: LicenseProduct): LicenseToken {
        if (payload.dev != device) throw LicenseTokenError.OtherDevice
        val plan = LicensePlan.entries.firstOrNull { it.name.equals(payload.plan, ignoreCase = true) }
            ?: throw LicenseTokenError.Malformed
        val product = LicenseProduct.entries.firstOrNull { it.name.equals(payload.prod, ignoreCase = true) }
            ?: throw LicenseTokenError.Malformed
        if (!product.covers(app)) throw LicenseTokenError.OtherProduct
        payload.exp?.let { if (it < now) throw LicenseTokenError.Expired(it) }
        return LicenseToken(payload.dev, payload.lic, plan, product, payload.iat, payload.exp)
    }

    private fun signatureValid(publicKey: String, data: ByteArray, signature: ByteArray): Boolean {
        val key = runCatching { Ed25519PublicKeyParameters(Base64.getDecoder().decode(publicKey), 0) }
            .getOrNull() ?: return false
        val signer = Ed25519Signer()
        signer.init(false, key)
        signer.update(data, 0, data.size)
        return signer.verifySignature(signature)
    }

    private fun decode(part: String): ByteArray? =
        runCatching { Base64.getUrlDecoder().decode(part) }.getOrNull()
}

/** Activation codes as people type them. */
object ActivationCode {
    private const val ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

    /** Canonical "XXXXX-XXXXX-XXXXX-XXXXX", or null. */
    fun normalize(input: String): String? {
        val cleaned = input.uppercase().filter { it.isLetterOrDigit() }.map {
            when (it) {
                'O' -> '0'
                'I', 'L' -> '1'
                else -> it
            }
        }
        if (cleaned.size != 20 || cleaned.any { it !in ALPHABET }) return null
        return cleaned.joinToString("").chunked(5).joinToString("-")
    }
}
