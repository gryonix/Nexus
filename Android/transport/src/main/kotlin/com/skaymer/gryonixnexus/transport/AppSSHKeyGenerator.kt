package com.skaymer.gryonixnexus.transport

import com.skaymer.gryonixnexus.servercontrol.AppSSHIdentity
import java.security.SecureRandom
import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters

object AppSSHKeyGenerator {
    /** Ed25519 seeds are 32 bytes; anything else is not one */
    const val SEED_LENGTH = 32

    /** A brand-new identity */
    fun generate(random: SecureRandom = SecureRandom()): AppSSHIdentity {
        val seed = ByteArray(SEED_LENGTH)
        random.nextBytes(seed)
        return identity(seed)
    }

    /** The identity for a seed already in the keystore */
    fun identity(seed: ByteArray): AppSSHIdentity =
        AppSSHIdentity(privateKeySeed = seed, ed25519PublicKey = publicKey(seed))

    /** The raw 32-byte Ed25519 public key for [seed] */
    fun publicKey(seed: ByteArray): ByteArray {
        require(seed.size == SEED_LENGTH) {
            "an ed25519 seed is $SEED_LENGTH bytes, got ${seed.size}"
        }
        return Ed25519PrivateKeyParameters(seed, 0).generatePublicKey().encoded
    }
}
