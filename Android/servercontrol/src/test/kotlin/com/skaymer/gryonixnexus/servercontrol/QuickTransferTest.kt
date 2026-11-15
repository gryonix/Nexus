package com.skaymer.gryonixnexus.servercontrol

import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.Test

class QuickTransferTest {
    private val key = ByteArray(32) { it.toByte() }

    @Test
    fun theTicketTextRoundTrips() {
        val ticket = QuickTransferTicket.fresh(50123, listOf("198.51.100.20", "203.0.113.4"))
        assertEquals(ticket, QuickTransferTicket.parse(ticket.text))
        assertTrue(ticket.text.startsWith("GXT1;"))
    }

    @Test
    fun foreignTextIsRefused() {
        assertNull(QuickTransferTicket.parse("WIFI:S:home;T:WPA;P:secret;;"))
        assertNull(QuickTransferTicket.parse("GXT1;AAAA;BBBB;1;"))
    }

    @Test
    fun addressesThatAreNotIPv4AreDropped() {
        val ticket = QuickTransferTicket.fresh(1, listOf("198.51.100.20", "example.net", "300.1.1.1", "fe80::1"))
        assertEquals(listOf("198.51.100.20"), QuickTransferTicket.parse(ticket.text)?.addresses)
    }

    @Test
    fun theBluetoothServiceMatchesTheAppleOne() {
        val ticket = QuickTransferTicket(ByteArray(16) { it.toByte() }, ByteArray(32) { 1 }, 1, emptyList())
        assertEquals("00010203-0405-0607-0809-0A0B0C0D0E0F", ticket.bluetoothService.toString().uppercase())
    }

    @Test
    fun theSealedFrameMatchesTheAppleVector() {
        val cipher = QuickTransferCipher(key)
        val sealed = cipher.seal("hello GXT1".toByteArray(), QuickTransferCipher.Direction.TO_SENDER, 0, ByteArray(12) { it.toByte() })
        assertEquals(APPLE_FRAME, sealed.toHex())
        assertEquals("hello GXT1", cipher.open(APPLE_FRAME.fromHex(), QuickTransferCipher.Direction.TO_SENDER, 0).decodeToString())
        assertEquals("5944", cipher.code(ByteArray(16) { it.toByte() }))
    }

    @Test
    fun appleCompressedBytesInflate() {
        assertEquals("""{"kind":"accept"}""", QuickTransferDeflate.decompress(APPLE_DEFLATED.fromHex()).decodeToString())
        val packed = QuickTransferDeflate.compress("""{"kind":"accept"}""".toByteArray())
        assertEquals("""{"kind":"accept"}""", QuickTransferDeflate.decompress(packed).decodeToString())
    }

    @Test
    fun framesOpenOnlyInTheirOwnDirectionAndOrder() {
        val cipher = QuickTransferCipher(key)
        val sealed = cipher.seal("hi".toByteArray(), QuickTransferCipher.Direction.TO_SENDER, 3)
        assertFailsWith<QuickTransferFailure.NotOurs> { cipher.open(sealed, QuickTransferCipher.Direction.TO_RECEIVER, 3) }
        assertFailsWith<QuickTransferFailure.NotOurs> { cipher.open(sealed, QuickTransferCipher.Direction.TO_SENDER, 4) }
        assertFailsWith<QuickTransferFailure.NotOurs> {
            QuickTransferCipher(ByteArray(32) { 7 }).open(sealed, QuickTransferCipher.Direction.TO_SENDER, 3)
        }
    }

    @Test
    fun payloadsSurviveAnySplit() {
        val payloads = listOf("one".toByteArray(), ByteArray(1000) { 9 }, "three".toByteArray())
        val stream = payloads.map(QuickTransferFrames::frame).reduce { a, b -> a + b }
        val frames = QuickTransferFrames()
        val out = QuickTransferInbound.chunks(stream, 7).flatMap(frames::append)
        assertEquals(payloads.map { it.toList() }, out.map { it.toList() })
    }

    @Test
    fun theWholeConversationOverMemory() = runBlocking<Unit> {
        val (a, b) = MemoryLink.pair()
        converse(a, b)
    }

    @Test
    fun theWholeConversationOverTcp() = runBlocking<Unit> {
        val listener = QuickTransferTcpListener()
        val accepted = Channel<QuickTransferLink>(1)
        listener.start { accepted.trySend(it) }
        try {
            val receiver = QuickTransferTcpLink.connectFirst(listOf("127.0.0.1"), listener.port)
            converse(accepted.receive(), receiver)
        } finally {
            listener.stop()
        }
    }

    @Test
    fun aDeclineReachesTheReceiver() = runBlocking<Unit> {
        val (a, b) = MemoryLink.pair()
        val sender = QuickTransferChannel(a, key, QuickTransferChannel.Role.SENDER)
        val receiver = QuickTransferChannel(b, key, QuickTransferChannel.Role.RECEIVER)
        QuickTransferFlow.knock(receiver, "Phone")
        QuickTransferFlow.greet(sender)
        QuickTransferFlow.decline(sender)
        assertFailsWith<QuickTransferFailure.Declined> { QuickTransferFlow.awaitAnswer(receiver) }
    }

    @Test
    fun theRaceTakesTheFirstLinkAndClosesTheLate() = runBlocking<Unit> {
        val (fast, _) = MemoryLink.pair()
        val (slow, slowPeer) = MemoryLink.pair()
        val winner = QuickTransferRace.first(
            listOf({ throw QuickTransferFailure.Closed() }, { fast }, {
                withContext(NonCancellable) { delay(100) }
                slow
            }),
            5000,
        )
        assertTrue(winner === fast)
        assertFailsWith<QuickTransferFailure.Closed> { withTimeout(5000) { slowPeer.receive() } }
    }

    private suspend fun converse(senderLink: QuickTransferLink, receiverLink: QuickTransferLink) = coroutineScope {
        val sender = QuickTransferChannel(senderLink, key, QuickTransferChannel.Role.SENDER)
        val receiver = QuickTransferChannel(receiverLink, key, QuickTransferChannel.Role.RECEIVER)
        val servers = listOf("{\"deployment\":1}".repeat(2000), "{}")
        val shown = QuickTransferFlow.knock(receiver, "Pixel")
        assertEquals(QuickTransferFlow.Hello("Pixel", shown), QuickTransferFlow.greet(sender))
        QuickTransferFlow.accept(sender)
        QuickTransferFlow.awaitAnswer(receiver)
        val delivered = async { QuickTransferFlow.deliver(sender, servers) }
        assertEquals(servers, QuickTransferFlow.collect(receiver))
        assertEquals(2, delivered.await())
    }

    private class MemoryLink : QuickTransferLink {
        private val inbox = Channel<ByteArray>(Channel.UNLIMITED)
        var peer: MemoryLink? = null

        override suspend fun send(payload: ByteArray) {
            peer?.inbox?.send(payload) ?: throw QuickTransferFailure.Closed()
        }

        override suspend fun receive(): ByteArray =
            inbox.receiveCatching().getOrNull() ?: throw QuickTransferFailure.Closed()

        override fun close() {
            peer?.inbox?.close()
        }

        companion object {
            fun pair(): Pair<MemoryLink, MemoryLink> {
                val a = MemoryLink()
                val b = MemoryLink()
                a.peer = b
                b.peer = a
                return a to b
            }
        }
    }

    private fun ByteArray.toHex() = joinToString("") { "%02x".format(it) }

    private fun String.fromHex() = chunked(2).map { it.toInt(16).toByte() }.toByteArray()

    private companion object {
        const val APPLE_FRAME = "000102030405060708090a0b2f67ba77aac58543d9707e4d63576133e433ae6a2c1d84c9c746"
        const val APPLE_DEFLATED = "ab56cacecc4b51b2524a4c4e4e2d2851aa0500"
    }
}
