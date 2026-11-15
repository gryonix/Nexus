package com.skaymer.gryonixnexus.transport

import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicInteger
import net.schmizz.sshj.SSHClient
import net.schmizz.sshj.connection.channel.direct.Parameters

/** One local listener forwarding to a remote host through SSH */
class PortForwarder(private val client: SSHClient) {
    private val accepted = AtomicInteger(0)
    private var socket: ServerSocket? = null

    /** Connections taken since the forward started */
    val connections: Int get() = accepted.get()

    fun start(localPort: Int, remoteHost: String, remotePort: Int) {
        val server = object : ServerSocket() {
            override fun accept(): Socket = super.accept().also { accepted.incrementAndGet() }
        }.apply {
            reuseAddress = true
            bind(InetSocketAddress("127.0.0.1", localPort))
        }
        socket = server
        val forwarder = client.newLocalPortForwarder(Parameters("127.0.0.1", localPort, remoteHost, remotePort), server)
        Thread({ runCatching { forwarder.listen() } }, "port-forward-$localPort").apply { isDaemon = true; start() }
    }

    fun stop() {
        runCatching { socket?.close() }
        socket = null
    }
}
