package com.skaymer.gryonixnexus.tvlink

import java.io.File
import java.math.BigInteger
import java.security.KeyFactory
import java.security.spec.ECPrivateKeySpec
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.bouncycastle.jce.ECNamedCurveTable
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class TvLinkGoldenTest {
    @Serializable
    data class Frame(val from: String, val hex: String)

    @Serializable
    data class Message(val from: String, val json: String)

    @Serializable
    data class Golden(
        val phone: TvPeer,
        val tv: TvPeer,
        val code: Int,
        val pairingPhoneRandom: List<String>,
        val pairingFrames: List<Frame>,
        val pairingKey: String,
        val sessionPhoneRandom: List<String>,
        val sessionFrames: List<Frame>,
        val sessionMessages: List<Message>,
    )

    private fun repoRoot(): File {
        var here: File? = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (here != null && !File(here, "settings.gradle.kts").isFile) here = here.parentFile
        return requireNotNull(requireNotNull(here).parentFile)
    }

    private val golden: Golden by lazy {
        val file = File(repoRoot(), "Apple/Packages/gryonixNexus/Tests/TVLinkTests/Resources/tvlink-golden.json")
        assertTrue(file.isFile, "no golden file at ${file.path}")
        Json { ignoreUnknownKeys = true }.decodeFromString(Golden.serializer(), file.readText())
    }

    class Scripted(values: List<String>) : TvLinkRandom {
        private val queue = ArrayDeque(values.map(::hex))

        override fun bytes(count: Int): ByteArray = queue.removeFirst().also { assertEquals(count, it.size) }

        override fun keyPair(): TvKeyPair {
            val scalar = BigInteger(1, queue.removeFirst())
            val curve = ECNamedCurveTable.getParameterSpec("secp256r1")
            val point = curve.g.multiply(scalar).normalize()
            val private = KeyFactory.getInstance("EC").generatePrivate(ECPrivateKeySpec(scalar, TvCrypto.p256))
            val public = byteArrayOf(4) + point.affineXCoord.encoded + point.affineYCoord.encoded
            return TvKeyPair(private, public)
        }
    }

    @Test
    fun `pairing puts the same bytes on the wire and ends on the same key`() {
        val frames = golden.pairingFrames.map { it.from to hex(it.hex) }
        val phone = TvPairingPhone(golden.phone, Scripted(golden.pairingPhoneRandom))
        var index = 0
        fun nextPhone(): ByteArray = frames[index].also { assertEquals("phone", it.first, "frame $index") }.second.also { index++ }
        fun nextTv(): ByteArray = frames[index].also { assertEquals("tv", it.first, "frame $index") }.second.also { index++ }

        assertArrayEquals(nextPhone(), phone.hello().encoded(), "hello")
        assertEquals(TvPairingPhone.Step.NeedsCode, phone.receive(TvHandshakeMessage.decode(nextTv())))
        assertEquals(golden.tv, phone.tv)
        assertArrayEquals(nextPhone(), phone.enter(TvPairingCode.of(golden.code)!!).encoded(), "first commitment")
        var result: TvPairingResult? = null
        while (result == null) {
            when (val step = phone.receive(TvHandshakeMessage.decode(nextTv()))) {
                is TvPairingPhone.Step.Send -> assertArrayEquals(nextPhone(), step.message.encoded(), "frame ${index - 1}")
                is TvPairingPhone.Step.SendSealed -> {
                    assertArrayEquals(nextPhone(), step.frame, "sealed confirmation")
                    result = phone.receiveSealed(nextTv())
                }
                TvPairingPhone.Step.NeedsCode -> error("code asked twice")
            }
        }
        assertEquals(frames.size, index, "every frame was used")
        assertEquals(golden.pairingKey, result.pairingKey.toHex())
        assertEquals(golden.tv, result.peer)
    }

    @Test
    fun `a session seals the same requests and opens the TV's answers`() {
        val frames = golden.sessionFrames.map { hex(it.hex) }
        val session = TvSessionPhone(golden.phone, golden.tv.id, hex(golden.pairingKey), Scripted(golden.sessionPhoneRandom))
        assertArrayEquals(frames[0], session.hello().encoded(), "session hello")
        val channel = session.receive(TvHandshakeMessage.decode(frames[1]))

        golden.sessionMessages.chunked(2).forEachIndexed { k, (request, answer) ->
            val message = TvMessage.decode(request.json.toByteArray())
            assertEquals(request.json, message.encoded().decodeToString(), "the request's JSON, byte for byte")
            assertArrayEquals(frames[2 + 2 * k], channel.seal(message), "request $k sealed")
            val opened = channel.openMessage(frames[3 + 2 * k])
            assertEquals(TvMessage.decode(answer.json.toByteArray()), opened, "answer $k")
            assertEquals(answer.json, opened.encoded().decodeToString())
        }
    }

    @Test
    fun `a wrong code is caught on the phone too`() {
        // Replaying the TV's frames with another code: the TV's first reveal
        // does not match what this phone committed to.
        val frames = golden.pairingFrames.map { hex(it.hex) }
        val phone = TvPairingPhone(golden.phone, Scripted(golden.pairingPhoneRandom))
        phone.hello()
        phone.receive(TvHandshakeMessage.decode(frames[1]))
        val wrong = TvPairingCode.of(golden.code xor 1)!!
        phone.enter(wrong)
        phone.receive(TvHandshakeMessage.decode(frames[3]))
        val error = runCatching { phone.receive(TvHandshakeMessage.decode(frames[5])) }.exceptionOrNull()
        assertTrue(error is TvLinkException.CodeMismatch, "got $error")
    }

    companion object {
        fun hex(text: String): ByteArray = ByteArray(text.length / 2) { text.substring(2 * it, 2 * it + 2).toInt(16).toByte() }
        fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }
    }
}
