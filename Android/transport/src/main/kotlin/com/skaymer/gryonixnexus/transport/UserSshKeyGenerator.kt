package com.skaymer.gryonixnexus.transport

import com.skaymer.gryonixnexus.servercontrol.OpenSshKeyEncoding
import com.skaymer.gryonixnexus.servercontrol.SshKeyKind
import com.skaymer.gryonixnexus.servercontrol.SshKeyMaterial
import com.skaymer.gryonixnexus.servercontrol.UserSshKey
import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.SecureRandom
import java.security.interfaces.ECPrivateKey
import java.security.interfaces.ECPublicKey
import java.security.interfaces.RSAPrivateCrtKey
import java.security.spec.ECGenParameterSpec
import java.util.UUID
import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters

/** Makes new user keys */
object UserSshKeyGenerator {
    const val COMMENT = "gryonixnexus-app"

    fun generate(kind: SshKeyKind, name: String, nowMillis: Long = System.currentTimeMillis()): UserSshKey {
        val material = material(kind)
        return UserSshKey(
            id = UUID.randomUUID().toString(),
            name = name,
            kind = kind,
            createdAtMillis = nowMillis,
            publicKey = OpenSshKeyEncoding.publicLine(material, kind, COMMENT),
            privateKeyPem = OpenSshKeyEncoding.privatePem(material, COMMENT),
        )
    }

    fun material(kind: SshKeyKind): SshKeyMaterial = when (kind) {
        SshKeyKind.ED25519 -> ed25519()
        SshKeyKind.ECDSA_P256 -> ecdsa()
        SshKeyKind.RSA_3072, SshKeyKind.RSA_4096 -> rsa(kind.bits)
    }

    private fun ed25519(): SshKeyMaterial {
        val seed = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val publicKey = Ed25519PrivateKeyParameters(seed, 0).generatePublicKey().encoded
        return SshKeyMaterial.Ed25519(seed, publicKey)
    }

    private fun ecdsa(): SshKeyMaterial {
        val generator = KeyPairGenerator.getInstance("EC")
        generator.initialize(ECGenParameterSpec("secp256r1"))
        val pair = generator.generateKeyPair()
        val point = (pair.public as ECPublicKey).w
        val encoded = byteArrayOf(4) + fixed32(point.affineX) + fixed32(point.affineY)
        return SshKeyMaterial.EcdsaP256(encoded, (pair.private as ECPrivateKey).s)
    }

    private fun fixed32(value: BigInteger): ByteArray {
        val raw = value.toByteArray().dropWhile { it == 0.toByte() }.toByteArray()
        return ByteArray(32 - raw.size) + raw
    }

    private fun rsa(bits: Int): SshKeyMaterial {
        val generator = KeyPairGenerator.getInstance("RSA")
        generator.initialize(bits)
        val key = generator.generateKeyPair().private as RSAPrivateCrtKey
        return SshKeyMaterial.Rsa(
            key.modulus, key.publicExponent, key.privateExponent,
            key.crtCoefficient, key.primeP, key.primeQ,
        )
    }
}
