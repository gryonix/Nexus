package com.skaymer.gryonixnexus.agentclient

import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class ConnectEnvelopeTest {
    /** The same assertion, byte for byte, as the agent's `envelope_frames_flag_and_big_endian_length` */
    @Test
    fun `a frame is a flag then a big-endian length then the payload`() {
        val framed = ConnectEnvelope.encode("hello".toByteArray())
        assertEquals(0x00, framed[0].toInt())
        assertContentEquals(byteArrayOf(0, 0, 0, 5), framed.copyOfRange(1, 5))
        assertContentEquals("hello".toByteArray(), framed.copyOfRange(5, framed.size))
    }

    @Test
    fun `a length with the high bit set survives the round trip`() {
        val payload = ByteArray(200) { it.toByte() }
        val decoder = ConnectEnvelope.Decoder()
        decoder.append(ConnectEnvelope.encode(payload))

        val frame = decoder.next()
        assertContentEquals(payload, frame?.payload)
        assertNull(decoder.next(), "one frame in, one frame out")
    }

    @Test
    fun `an impossible frame length is refused instead of waited for`() {
        val decoder = ConnectEnvelope.Decoder()
        decoder.append(byteArrayOf(0, 0x7f, 0xff.toByte(), 0xff.toByte(), 0xff.toByte()))
        kotlin.test.assertFailsWith<AgentError.Transport> { decoder.next() }
    }

    @Test
    fun `a payload past 64KB frames its length across bytes`() {
        val payload = ByteArray(70_000) { (it % 251).toByte() }
        val framed = ConnectEnvelope.encode(payload)
        assertContentEquals(byteArrayOf(0, 0x01, 0x11, 0x70.toByte()), framed.copyOfRange(1, 5))

        val decoder = ConnectEnvelope.Decoder()
        decoder.append(framed)
        assertContentEquals(payload, decoder.next()?.payload)
    }

    /** The reason the decoder is incremental at all */
    @Test
    fun `a frame split across reads completes only when it is whole`() {
        val framed = ConnectEnvelope.encode("installing".toByteArray())
        val decoder = ConnectEnvelope.Decoder()

        decoder.append(framed.copyOfRange(0, 3))
        assertNull(decoder.next(), "not even the header is complete yet")
        decoder.append(framed.copyOfRange(3, 8))
        assertNull(decoder.next(), "header is in, payload is not")
        decoder.append(framed.copyOfRange(8, framed.size))
        assertContentEquals("installing".toByteArray(), decoder.next()?.payload)
    }

    @Test
    fun `several frames in one read come out one at a time`() {
        val decoder = ConnectEnvelope.Decoder()
        decoder.append(
            ConnectEnvelope.encode("one".toByteArray()) +
                ConnectEnvelope.encode("two".toByteArray()) +
                ConnectEnvelope.encode("three".toByteArray()),
        )
        assertContentEquals("one".toByteArray(), decoder.next()?.payload)
        assertContentEquals("two".toByteArray(), decoder.next()?.payload)
        assertContentEquals("three".toByteArray(), decoder.next()?.payload)
        assertNull(decoder.next())
    }

    @Test
    fun `the end-of-stream flag is what marks the trailer`() {
        val decoder = ConnectEnvelope.Decoder()
        decoder.append(ConnectEnvelope.encode("progress".toByteArray()))
        decoder.append(
            ConnectEnvelope.encode(
                """{"error":{"code":"internal"}}""".toByteArray(),
                ConnectEnvelope.END_OF_STREAM_FLAG,
            ),
        )
        assertEquals(false, decoder.next()?.isEndOfStream)
        assertTrue(decoder.next()?.isEndOfStream == true)
    }

    @Test
    fun `an empty payload still frames and decodes`() {
        val decoder = ConnectEnvelope.Decoder()
        decoder.append(ConnectEnvelope.encode(ByteArray(0)))
        val frame = decoder.next()
        assertEquals(0, frame?.payload?.size)
    }
}
