package com.skaymer.gryonixnexus.servercontrol

/** The two sides of a transfer conversation */
object QuickTransferFlow {
    data class Hello(val device: String, val code: String)

    /** Reads the first message; anything but our hello is refused */
    suspend fun greet(channel: QuickTransferChannel): Hello {
        val message = channel.receive()
        val nonce = message.nonce?.let(QuickTransferTicket::decode)
        if (message.kind != QuickTransferMessage.HELLO || nonce == null || nonce.size != 16) {
            throw QuickTransferFailure.Unexpected()
        }
        return Hello((message.device ?: "").take(64), channel.code(nonce))
    }

    suspend fun accept(channel: QuickTransferChannel) = channel.send(QuickTransferMessage(QuickTransferMessage.ACCEPT))

    suspend fun decline(channel: QuickTransferChannel) {
        runCatching { channel.send(QuickTransferMessage(QuickTransferMessage.DECLINE)) }
        channel.close()
    }

    /** Sends the servers and waits for the count imported */
    suspend fun deliver(channel: QuickTransferChannel, servers: List<String>): Int {
        channel.send(QuickTransferMessage(QuickTransferMessage.SERVERS, servers = servers))
        val reply = channel.receive()
        if (reply.kind != QuickTransferMessage.DONE) throw QuickTransferFailure.Unexpected()
        return reply.imported ?: servers.size
    }

    /** Says hello; returns the code to show */
    suspend fun knock(
        channel: QuickTransferChannel,
        device: String,
        nonce: ByteArray = TransferSeal.randomBytes(16),
    ): String {
        channel.send(QuickTransferMessage(QuickTransferMessage.HELLO, device = device, nonce = QuickTransferTicket.encode(nonce)))
        return channel.code(nonce)
    }

    /** Waits for the sender's answer */
    suspend fun awaitAnswer(channel: QuickTransferChannel) {
        when (channel.receive().kind) {
            QuickTransferMessage.ACCEPT -> Unit
            QuickTransferMessage.DECLINE -> throw QuickTransferFailure.Declined()
            else -> throw QuickTransferFailure.Unexpected()
        }
    }

    /** Receives the servers and confirms them */
    suspend fun collect(channel: QuickTransferChannel): List<String> {
        val message = channel.receive()
        val servers = message.servers
        if (message.kind != QuickTransferMessage.SERVERS || servers == null) throw QuickTransferFailure.Unexpected()
        channel.send(QuickTransferMessage(QuickTransferMessage.DONE, imported = servers.size))
        return servers
    }
}
