package com.skaymer.gryonixnexus.recipe

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Test
import java.util.Base64

/** The hand-written X25519 against RFC 7748's own answers */
class Curve25519Test {
    private fun hex(text: String): ByteArray =
        ByteArray(text.length / 2) { text.substring(it * 2, it * 2 + 2).toInt(16).toByte() }

    private fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it) }

    /** RFC 7748 §5.2, the two scalar-multiplication vectors */
    @Test
    fun `the ladder answers the RFC's scalar multiplication vectors`() {
        assertEquals(
            "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552",
            hex(Curve25519.scalarMultiply(
                hex("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4"),
                hex("e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c")
            ))
        )
        assertEquals(
            "95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957",
            hex(Curve25519.scalarMultiply(
                hex("4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d"),
                hex("e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493")
            ))
        )
    }

    /**
     * RFC 7748 §6.1: Alice's and Bob's public keys, and the shared secret
     * both sides arrive at. The shared secret is what a WireGuard peer
     * actually computes, so agreement — not just a well-formed key — is the
     * property worth pinning.
     */
    @Test
    fun `the RFC's Diffie-Hellman example agrees on both sides`() {
        val alicePrivate = hex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
        val bobPrivate = hex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb")
        val alicePublic = Curve25519.publicKey(alicePrivate)
        val bobPublic = Curve25519.publicKey(bobPrivate)
        assertEquals("8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a",
                     hex(alicePublic))
        assertEquals("de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f",
                     hex(bobPublic))
        val shared = "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"
        assertEquals(shared, hex(Curve25519.scalarMultiply(alicePrivate, bobPublic)))
        assertEquals(shared, hex(Curve25519.scalarMultiply(bobPrivate, alicePublic)))
    }

    @Test
    fun `a generated pair is wg-shaped and internally consistent`() {
        val pair = SecureRandomWireGuardKeyProvider().makeKeyPair(WireGuardKeySlot.VPS)
        val decoder = Base64.getDecoder()
        val privateKey = decoder.decode(pair.privateKey)
        val publicKey = decoder.decode(pair.publicKey)
        assertEquals(32, privateKey.size)
        assertEquals(32, publicKey.size)
        assertEquals(hex(publicKey), hex(Curve25519.publicKey(privateKey)))
        assertEquals(0, privateKey[0].toInt() and 7, "the low three bits are not clamped")
        assertEquals(64, privateKey[31].toInt() and 192, "the top two bits are not clamped")
        assertNotEquals(pair.privateKey,
                        SecureRandomWireGuardKeyProvider().makeKeyPair(WireGuardKeySlot.VPS).privateKey)
    }
}
