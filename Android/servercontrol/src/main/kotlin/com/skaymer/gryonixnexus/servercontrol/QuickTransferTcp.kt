package com.skaymer.gryonixnexus.servercontrol

import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/** A transfer link over one TCP connection */
class QuickTransferTcpLink(private val socket: Socket) : QuickTransferLink {
    private val input = DataInputStream(socket.getInputStream().buffered())
    private val output = DataOutputStream(socket.getOutputStream().buffered())

    override suspend fun send(payload: ByteArray) = withContext(Dispatchers.IO) {
        runCatching {
            output.write(QuickTransferFrames.frame(payload))
            output.flush()
        }.getOrElse { throw QuickTransferFailure.Closed() }
    }

    override suspend fun receive(): ByteArray = withContext(Dispatchers.IO) {
        runCatching {
            val length = input.readInt().toLong() and 0xffffffffL
            if (length > QuickTransferFrames.MAXIMUM) throw QuickTransferFailure.TooLarge()
            ByteArray(length.toInt()).also(input::readFully)
        }.getOrElse { if (it is QuickTransferFailure) throw it else throw QuickTransferFailure.Closed() }
    }

    override fun close() {
        runCatching { socket.close() }
    }

    companion object {
        suspend fun connect(host: String, port: Int, timeoutMillis: Int): QuickTransferTcpLink =
            withContext(Dispatchers.IO) {
                val socket = Socket()
                runCatching { socket.connect(InetSocketAddress(host, port), timeoutMillis) }
                    .getOrElse {
                        socket.close()
                        throw QuickTransferFailure.Closed()
                    }
                if (!isActive) socket.close()
                ensureActive()
                socket.tcpNoDelay = true
                QuickTransferTcpLink(socket)
            }

        /** Connects to the first address that answers */
        suspend fun connectFirst(addresses: List<String>, port: Int, timeoutMillis: Int = 4000): QuickTransferLink =
            QuickTransferRace.first(addresses.map { address -> { connect(address, port, timeoutMillis) } }, timeoutMillis + 1000L)
    }
}

/** Waits for receivers on a free TCP port */
class QuickTransferTcpListener {
    private val server = ServerSocket(0)
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    val port: Int get() = server.localPort

    fun start(onLink: (QuickTransferLink) -> Unit) {
        scope.launch {
            while (!server.isClosed) {
                val socket = runCatching { server.accept() }.getOrNull() ?: break
                socket.tcpNoDelay = true
                onLink(QuickTransferTcpLink(socket))
            }
        }
    }

    fun stop() {
        runCatching { server.close() }
        scope.cancel()
    }
}

/** The first link to connect wins; the rest close */
object QuickTransferRace {
    suspend fun first(attempts: List<suspend () -> QuickTransferLink>, timeoutMillis: Long): QuickTransferLink {
        val winner = CompletableDeferred<QuickTransferLink>()
        val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val jobs = attempts.map { attempt ->
            scope.launch {
                runCatching { attempt() }.onSuccess { link -> if (!winner.complete(link)) link.close() }
            }
        }
        scope.launch {
            jobs.joinAll()
            winner.completeExceptionally(QuickTransferFailure.Closed())
        }
        try {
            return withTimeoutOrNull(timeoutMillis) { winner.await() } ?: throw QuickTransferFailure.TimedOut()
        } finally {
            if (!winner.isCompleted) winner.completeExceptionally(QuickTransferFailure.TimedOut())
            jobs.forEach { it.cancel() }
        }
    }
}

/** This device's IPv4 addresses on Wi-Fi, Ethernet or a hotspot */
object QuickTransferAddresses {
    private val prefixes = listOf("wlan", "eth", "ap", "swlan", "en", "bridge", "rndis")
    private const val LIMIT = 4

    fun current(): List<String> = runCatching {
        NetworkInterface.getNetworkInterfaces().toList()
            .filter { it.isUp && !it.isLoopback && !it.isVirtual && prefixes.any(it.name::startsWith) }
            .sortedBy { if (it.name.startsWith("wlan")) 0 else 1 }
            .flatMap { it.inetAddresses.toList() }
            .filterIsInstance<Inet4Address>()
            .filter { !it.isLinkLocalAddress && !it.isLoopbackAddress }
            .mapNotNull { it.hostAddress }
            .distinct()
            .take(LIMIT)
    }.getOrDefault(emptyList())
}
