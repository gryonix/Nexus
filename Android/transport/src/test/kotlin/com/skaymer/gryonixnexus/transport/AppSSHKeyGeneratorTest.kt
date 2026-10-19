package com.skaymer.gryonixnexus.transport

import com.skaymer.gryonixnexus.servercontrol.OpenSSHPublicKey
import java.security.SecureRandom
import java.util.Base64
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class AppSSHKeyGeneratorTest {
    private fun hex(text: String) = text.chunked(2).map { it.toInt(16).toByte() }.toByteArray()

    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }

    private val vectors = listOf(
        "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60" to
            "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
        "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb" to
            "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
        "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7" to
            "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025",
    )

    @Test
    fun `the public key is the one RFC 8032 says the seed produces`() {
        for ((seed, expected) in vectors) {
            assertEquals(expected, hex(AppSSHKeyGenerator.publicKey(hex(seed))), "seed $seed")
        }
    }

    @Test
    fun `a seed that is not 32 bytes is refused`() {
        for (size in listOf(0, 16, 31, 33, 64)) {
            val error = assertFailsWith<IllegalArgumentException> {
                AppSSHKeyGenerator.publicKey(ByteArray(size))
            }
            assertTrue(error.message.orEmpty().contains("$size"), error.message.orEmpty())
        }
    }

    /** The whole round trip: seed in, `authorized_keys` line out */
    @Test
    fun `the identity carries the seed and the authorized_keys line for it`() {
        val (seed, expectedPublic) = vectors[0]

        val identity = AppSSHKeyGenerator.identity(hex(seed))

        assertContentEquals(hex(seed), identity.privateKeySeed)
        assertTrue(identity.publicKeyOpenSSH.startsWith("ssh-ed25519 "), identity.publicKeyOpenSSH)
        assertTrue(identity.publicKeyOpenSSH.endsWith(" ${OpenSSHPublicKey.DEFAULT_COMMENT}"))

        val blob = Base64.getDecoder().decode(identity.publicKeyOpenSSH.split(" ")[1])
        assertEquals(expectedPublic, hex(blob.copyOfRange(blob.size - 32, blob.size)))
        assertEquals(4 + "ssh-ed25519".length + 4 + 32, blob.size)
    }

    @Test
    fun `a generated identity uses exactly the seed the randomness gave it`() {
        val (seed, expectedPublic) = vectors[1]
        val fixed = object : SecureRandom() {
            override fun nextBytes(bytes: ByteArray) {
                hex(seed).copyInto(bytes)
            }
        }

        val identity = AppSSHKeyGenerator.generate(fixed)

        assertContentEquals(hex(seed), identity.privateKeySeed)
        assertEquals(expectedPublic, hex(AppSSHKeyGenerator.publicKey(identity.privateKeySeed)))
    }

    /** Two real generations must not agree */
    @Test
    fun `two generated identities differ`() {
        val first = AppSSHKeyGenerator.generate()
        val second = AppSSHKeyGenerator.generate()

        assertTrue(!first.privateKeySeed.contentEquals(second.privateKeySeed), "the seed repeated")
        assertTrue(first.publicKeyOpenSSH != second.publicKeyOpenSSH, "the public key repeated")
        assertEquals(AppSSHKeyGenerator.SEED_LENGTH, first.privateKeySeed.size)
    }

    @Test
    fun `re-deriving a stored seed reproduces the same line`() {
        val stored = AppSSHKeyGenerator.generate()
        assertEquals(stored, AppSSHKeyGenerator.identity(stored.privateKeySeed))
    }
}
