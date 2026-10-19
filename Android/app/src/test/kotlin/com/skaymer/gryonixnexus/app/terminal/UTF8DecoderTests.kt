package com.skaymer.gryonixnexus.app.terminal

import kotlin.test.assertEquals
import org.junit.jupiter.api.Test

/** UTF-8 across reads */
class UTF8DecoderTests {
    private fun decode(vararg chunks: ByteArray): String {
        val decoder = UTF8Decoder()
        val out = StringBuilder()
        chunks.forEach { chunk -> chunk.forEach { byte -> decoder.decode(byte) { out.append(it) } } }
        return out.toString()
    }

    @Test
    fun `a character split across two reads survives it`() {
        val bytes = "Марина".toByteArray(Charsets.UTF_8)
        val first = bytes.copyOfRange(0, 3)
        val second = bytes.copyOfRange(3, bytes.size)
        assertEquals("Марина", decode(first, second))
    }

    @Test
    fun `a character split byte by byte survives that too`() {
        val bytes = "日本語".toByteArray(Charsets.UTF_8)
        val perByte = bytes.map { byteArrayOf(it) }.toTypedArray()
        assertEquals("日本語", decode(*perByte))
    }

    @Test
    fun `an emoji comes back whole`() {
        val bytes = "ok 🚀".toByteArray(Charsets.UTF_8)
        assertEquals("ok 🚀", decode(bytes))
    }

    @Test
    fun `a broken sequence becomes one replacement and does not eat what follows`() {
        val decoded = decode(byteArrayOf(0xC3.toByte()) + "ok".toByteArray(Charsets.UTF_8))
        assertEquals("�ok", decoded)
    }

    @Test
    fun `a stray continuation byte is refused rather than joined to anything`() {
        assertEquals("�a", decode(byteArrayOf(0x80.toByte(), 'a'.code.toByte())))
    }

    @Test
    fun `an overlong form is refused`() {
        assertEquals("�", decode(byteArrayOf(0xC0.toByte(), 0x80.toByte())))
    }

    @Test
    fun `a surrogate half encoded as UTF-8 is refused`() {
        assertEquals("�", decode(byteArrayOf(0xED.toByte(), 0xA0.toByte(), 0x80.toByte())))
    }

    @Test
    fun `plain ASCII is untouched`() {
        assertEquals("root@vps:~# ls -la", decode("root@vps:~# ls -la".toByteArray(Charsets.UTF_8)))
    }
}
