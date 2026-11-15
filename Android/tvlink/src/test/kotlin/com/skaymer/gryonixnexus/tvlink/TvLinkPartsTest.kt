package com.skaymer.gryonixnexus.tvlink

import java.nio.file.Files
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test

class TvLinkPartsTest {
    @Test
    fun `codes read the way people type them`() {
        assertEquals(482913, TvPairingCode.parse("482 913")?.value)
        assertEquals(4213, TvPairingCode.parse("004-213")?.value)
        assertNull(TvPairingCode.parse("12345"))
        assertNull(TvPairingCode.parse("12a456"))
        assertEquals("004 213", TvPairingCode.of(4213).toString())
        assertNull(TvPairingCode.of(1_000_000))
    }

    @Test
    fun `addresses and QR links read like the Swift side`() {
        assertEquals(TvAddress("192.0.2.10"), TvAddress.parse(" 192.0.2.10 "))
        assertEquals(TvAddress("192.0.2.10", 5000), TvAddress.parse("192.0.2.10:5000"))
        assertEquals(TvAddress("2001:db8::1", 5000), TvAddress.parse("[2001:db8::1]:5000"))
        assertEquals(TvAddress("2001:db8::1"), TvAddress.parse("2001:db8::1"))
        assertNull(TvAddress.parse("192.0.2.10:0"))
        assertNull(TvAddress.parse("a b"))

        val link = TvPairingLink(TvAddress("192.0.2.10", 47390), TvPairingCode.of(604217)!!, "Apple TV · draco")
        val text = TvPairingLink.format(link)
        assertEquals(link, TvPairingLink.parse(text))
        // What the TV draws (Swift's URLComponents) reads the same here
        assertEquals(
            link,
            TvPairingLink.parse("gryonixnexus://tv?host=192.0.2.10&port=47390&code=604217&name=Apple%20TV%20%C2%B7%20draco"),
        )
        assertNull(TvPairingLink.parse("https://tv?host=x&code=604217"))
    }

    @Test
    fun `frames survive arriving in pieces and refuse a hostile length`() {
        val stream = TvFrame.encode("hello".toByteArray()) + TvFrame.encode(ByteArray(70_000) { 7 })
        val reader = TvFrame.Reader()
        val frames = mutableListOf<ByteArray>()
        stream.toList().chunked(1000).forEach { piece ->
            reader.append(piece.toByteArray())
            while (true) frames += reader.next() ?: break
        }
        assertEquals(2, frames.size)
        assertArrayEquals("hello".toByteArray(), frames[0])
        val hostile = TvFrame.Reader().apply { append(byteArrayOf(0x7F, -1, -1, -1)) }
        assertThrows(TvLinkException.TooLarge::class.java) { hostile.next() }
    }

    @Test
    fun `sealed frames do not open replayed or altered`() {
        val sender = TvSecureChannel(ByteArray(32) { 1 }, ByteArray(32) { 2 })
        val receiver = TvSecureChannel(ByteArray(32) { 2 }, ByteArray(32) { 1 })
        val first = sender.seal("first".toByteArray())
        val second = sender.seal("second".toByteArray())
        val altered = first.copyOf().also { it[0] = (it[0].toInt() xor 1).toByte() }
        assertThrows(TvLinkException.CannotOpen::class.java) { receiver.open(altered) }
        assertThrows(TvLinkException.CannotOpen::class.java) { receiver.open(second) }
        assertArrayEquals("first".toByteArray(), receiver.open(first))
        assertThrows(TvLinkException.CannotOpen::class.java) { receiver.open(first) }
    }

    @Test
    fun `paired TVs keep their keys apart from the file`() {
        val secrets = object : TvSecretStoring {
            val map = mutableMapOf<String, String>()
            override fun secret(account: String) = map[account]
            override fun store(secret: String, account: String) { map[account] = secret }
            override fun delete(account: String) { map.remove(account) }
        }
        val dir = Files.createTempDirectory("tvlink").toFile()
        val store = TvPairedTvStore(dir.resolve("tvs.json"), secrets)
        store.save(TvPairedTv("tv-1", "draco", TvAddress("192.0.2.10"), 1), ByteArray(32) { 9 })
        assertEquals(listOf("tv-1"), store.all().map { it.id })
        assertArrayEquals(ByteArray(32) { 9 }, store.pairingKey("tv-1"))
        assertEquals(false, dir.resolve("tvs.json").readText().contains("CQkJ"), "the key is not in the file")
        store.remove("tv-1")
        assertEquals(emptyList<TvPairedTv>(), store.all())
        assertNull(store.pairingKey("tv-1"))
        dir.deleteRecursively()
    }

    @Test
    fun `a server travels as id, name and bundle, in Swift's order`() {
        val sent = TvSentServer(id = "s1", name = "draco", transfer = "YnVuZGxl")
        assertEquals(
            """{"id":"s1","name":"draco","transfer":"YnVuZGxl"}""",
            TvJson.encodeToString(TvSentServer.serializer(), sent),
        )
    }
}
