package com.skaymer.gryonixnexus.app.net

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

object MagicPacketSender {
    fun send(packet: ByteArray, host: String, port: Int): Boolean = try {
        DatagramSocket().use { socket ->
            socket.broadcast = true
            socket.send(DatagramPacket(packet, packet.size, InetAddress.getByName(host), port))
        }
        true
    } catch (failure: Exception) {
        false
    }
}
