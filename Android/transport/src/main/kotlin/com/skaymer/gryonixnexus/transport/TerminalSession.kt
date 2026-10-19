package com.skaymer.gryonixnexus.transport

import com.skaymer.gryonixnexus.servercontrol.ServerControlError
import java.io.StringReader
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import net.schmizz.sshj.SSHClient
import net.schmizz.sshj.connection.channel.direct.Session
import com.hierynomus.sshj.userauth.keyprovider.OpenSSHKeyV1KeyFile
import org.bouncycastle.jcajce.interfaces.EdDSAPrivateKey

/** Who to sign in as */
data class TerminalLogin(val username: String, val secret: Secret) {
    sealed class Secret {
        data class Password(val password: String) : Secret()

        class PrivateKeySeed(val seed: ByteArray) : Secret() {
            override fun equals(other: Any?) =
                other is PrivateKeySeed && seed.contentEquals(other.seed)

            override fun hashCode() = seed.contentHashCode()
        }
    }

    companion object {
        fun seedFromOpenSSHKey(text: String): ByteArray {
            val private: java.security.PrivateKey = runCatching {
                OpenSSHKeyV1KeyFile().apply {
                    init(StringReader(text), null as net.schmizz.sshj.userauth.password.PasswordFinder?)
                }.private
            }.getOrNull() ?: throw unreadable()

            val seed = (private as? EdDSAPrivateKey)?.let { key ->
                runCatching { key.encoded }.getOrNull()?.let { encoded ->
                    // PKCS#8 for Ed25519 ends with the 32 raw seed bytes.
                    encoded.takeIf { it.size >= 32 }?.copyOfRange(encoded.size - 32, encoded.size)
                }
            } ?: throw unreadable()

            if (seed.size != AppSSHKeyGenerator.SEED_LENGTH) throw unreadable()
            return seed
        }

        private fun unreadable() = ServerControlError.NotConfigured(
            "this does not look like an unencrypted OpenSSH ed25519 private key",
        )
    }
}

data class TerminalEndpoint(
    val host: String,
    val port: Int,
    val pinnedHostKey: String? = null,
    val parent: Hop? = null,
) {
    /** The machine in front of this one */
    data class Hop(
        val host: String,
        val port: Int,
        val pinnedHostKey: String?,
        val login: TerminalLogin,
    )
}

/** What a live terminal says */
sealed class TerminalEvent {
    class Output(val bytes: ByteArray) : TerminalEvent()

    /** The session ended */
    data class Closed(val reason: String?) : TerminalEvent()
}

/** One interactive shell over its own SSH connection */
class TerminalSession(
    private val endpoint: TerminalEndpoint,
    private val login: TerminalLogin,
    private val onPinHostKey: (String, String) -> Unit = { _, _ -> },
    private val dial: (TerminalEndpoint, TerminalLogin, (String, String) -> Unit) -> TerminalConnection =
        ::openConnection,
) {
    private val events = Channel<TerminalEvent>(capacity = 256)

    private val lock = Mutex()
    private var connection: TerminalConnection? = null
    private var session: Session? = null
    private var shell: Session.Shell? = null
    private var scope: CoroutineScope? = null

    @Volatile
    private var isOpen = false

    val output: Flow<TerminalEvent> get() = events.receiveAsFlow()

    /** Connect, ask for a pseudo-terminal, and start pumping its output */
    suspend fun start(columns: Int, rows: Int) {
        lock.withLock {
            if (connection != null) {
                throw ServerControlError.NotConfigured("this terminal is already open")
            }
            val connected = withContext(Dispatchers.IO) {
                runCatching { dial(endpoint, login, onPinHostKey) }
                    .getOrElse { error ->
                        if (error is ServerControlError) throw error
                        throw ServerControlError.ConnectionFailed(error.toString())
                    }
            }
            connection = connected

            withContext(Dispatchers.IO) {
                val opened = connected.client.startSession()
                opened.allocatePTY("xterm-256color", columns, rows, 0, 0, emptyMap())
                session = opened
                shell = opened.startShell()
            }
            isOpen = true

            val pump = CoroutineScope(SupervisorJob() + Dispatchers.IO)
            scope = pump
            pump.launch { drain() }
        }
    }

    suspend fun send(data: ByteArray) {
        if (!isOpen) return
        val stream = shell?.outputStream ?: return
        withContext(Dispatchers.IO) {
            runCatching { stream.write(data); stream.flush() }
        }
    }

    /** Tell the far end the window changed */
    suspend fun resize(columns: Int, rows: Int) {
        if (!isOpen) return
        val live = shell ?: return
        withContext(Dispatchers.IO) {
            runCatching { live.changeWindowDimensions(columns, rows, 0, 0) }
        }
    }

    /** Hang up */
    suspend fun close() {
        lock.withLock {
            isOpen = false
            scope?.cancel()
            scope = null
            shell = null
            events.close()
            val session = this.session
            val connection = this.connection
            this.session = null
            this.connection = null
            withContext(Dispatchers.IO) {
                runCatching { session?.close() }
                runCatching { connection?.close() }
            }
        }
    }

    // --------------------------------------------------------------- Private

    private suspend fun drain() {
        val live = shell ?: return
        val buffer = ByteArray(8 * 1024)
        var reason: String? = null
        try {
            while (true) {
                val read = live.inputStream.read(buffer)
                if (read < 0) break
                if (read > 0) events.send(TerminalEvent.Output(buffer.copyOf(read)))
            }
        } catch (_: kotlinx.coroutines.CancellationException) {
            return
        } catch (error: Exception) {
            reason = error.toString()
        }
        finish(reason)
    }

    private suspend fun finish(reason: String?) {
        if (!isOpen) return
        isOpen = false
        events.send(TerminalEvent.Closed(reason))
        events.close()
    }
}

/** A terminal's connection, and everything opened to reach it */
class TerminalConnection(
    val client: SSHClient,
    private val alsoClose: List<AutoCloseable> = emptyList(),
) : AutoCloseable {
    override fun close() {
        runCatching { client.disconnect() }
        alsoClose.forEach { runCatching { it.close() } }
    }
}

internal fun openConnection(
    endpoint: TerminalEndpoint,
    login: TerminalLogin,
    onPinHostKey: (String, String) -> Unit,
): TerminalConnection {
    val hop = endpoint.parent
        ?: return TerminalConnection(
            SSHClients.redialing {
                dialDirect(endpoint.host, endpoint.port, endpoint.pinnedHostKey, login, onPinHostKey)
            },
        )

    val through = SSHClients.redialing {
        dialDirect(hop.host, hop.port, hop.pinnedHostKey, hop.login, onPinHostKey)
    }
    val far = runCatching {
        dialDirect(endpoint.host, endpoint.port, endpoint.pinnedHostKey, login, onPinHostKey, via = through)
    }.getOrElse { failure ->
        runCatching { through.disconnect() }
        throw failure
    }
    return TerminalConnection(far, listOf(AutoCloseable { through.disconnect() }))
}

private fun dialDirect(
    host: String,
    port: Int,
    pin: String?,
    login: TerminalLogin,
    onPinHostKey: (String, String) -> Unit,
    via: SSHClient? = null,
): SSHClient {
    val client = SSHClients.create()
    client.addHostKeyVerifier(
        TOFUHostKeyVerifier(host, pin) { presented -> onPinHostKey(host, presented) },
    )
    return SSHClients.signIn(client) {
        if (via != null) connectVia(via.newDirectConnection(host, port)) else connect(host, port)
        when (val secret = login.secret) {
            is TerminalLogin.Secret.Password -> authPassword(login.username, secret.password)
            is TerminalLogin.Secret.PrivateKeySeed ->
                authPublickey(login.username, SSHJCommandRunner.keyProvider(secret.seed))
        }
    }
}
