package com.skaymer.gryonixnexus.transport

import net.schmizz.keepalive.KeepAliveProvider
import net.schmizz.sshj.DefaultConfig
import net.schmizz.sshj.SSHClient

/** sshj clients that give up on a dead connection */
object SSHClients {
    const val CONNECT_TIMEOUT_MS = 20_000
    const val KEEPALIVE_SECONDS = 10

    /** Pauses before redialling a server that hung up silently */
    val REDIAL_PAUSES_MS = listOf(15_000L, 30_000L)

    fun create(): SSHClient {
        val config = DefaultConfig().apply { keepAliveProvider = KeepAliveProvider.KEEP_ALIVE }
        return SSHClient(config).apply {
            connectTimeout = CONNECT_TIMEOUT_MS
            connection.keepAlive.keepAliveInterval = KEEPALIVE_SECONDS
        }
    }

    /** Connects and signs in; any failure closes the socket */
    fun signIn(client: SSHClient, steps: SSHClient.() -> Unit): SSHClient {
        try {
            client.steps()
            return client
        } catch (failure: Throwable) {
            runCatching { client.disconnect() }
            throw failure
        }
    }

    /** Runs [dial] again while the server hangs up before answering */
    fun <T> redialing(pauses: List<Long> = REDIAL_PAUSES_MS, dial: () -> T): T {
        for (pause in pauses) {
            try {
                return dial()
            } catch (failure: java.io.IOException) {
                if (!hungUpSilently(failure)) throw failure
            }
            Thread.sleep(pause)
        }
        try {
            return dial()
        } catch (failure: java.io.IOException) {
            if (!hungUpSilently(failure)) throw failure
            throw java.io.IOException(
                "the server closed the connection before answering; sshd may be refusing this address for a while",
                failure,
            )
        }
    }

    internal fun hungUpSilently(failure: Throwable): Boolean =
        generateSequence(failure) { it.cause }.take(4).any { cause ->
            val text = cause.message.orEmpty()
            text.contains("during identification exchange") ||
                (cause is java.net.SocketException && text.startsWith("Connection reset"))
        }
}
