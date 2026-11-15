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
import net.schmizz.sshj.userauth.UserAuthException
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
    /** Machines dialled before [parent], outermost first */
    val outer: List<Hop> = emptyList(),
    /** How this route reaches the machine */
    val kind: Kind = Kind.DIRECT,
    val connectTimeoutMs: Int = SSHClients.CONNECT_TIMEOUT_MS,
) {
    enum class Kind { DIRECT, LOCAL_NETWORK, RELAY, TUNNEL_ADDRESS, FALLBACK_ADDRESS }

    /** Every machine before this one, outermost first */
    val hops: List<Hop> get() = outer + listOfNotNull(parent)

    /** The address, and the machines in front of it */
    val summary: String
        get() = (hops.map { "${it.host}:${it.port}" } + "$host:$port").joinToString(" → ")

    /** The machine in front of this one */
    data class Hop(
        val host: String,
        val port: Int,
        val pinnedHostKey: String?,
        val login: TerminalLogin,
    )
}

/** Every route tried, each with why it failed */
class TerminalRoutesFailed(val attempts: List<Pair<TerminalEndpoint, String>>) :
    Exception(attempts.joinToString("\n") { (route, reason) -> "${route.summary}: $reason" })

/** What a live terminal says */
sealed class TerminalEvent {
    class Output(val bytes: ByteArray) : TerminalEvent()

    /** The session ended */
    data class Closed(val reason: String?) : TerminalEvent()
}

/** One shell over its own SSH connection, first answering route */
class TerminalSession(
    private val routes: List<TerminalEndpoint>,
    private val login: TerminalLogin,
    private val onPinHostKey: (String, String) -> Unit = { _, _ -> },
    /** The last argument says whether to redial a silent hang-up */
    private val dial: (TerminalEndpoint, TerminalLogin, (String, String) -> Unit, Boolean) -> TerminalConnection =
        ::openConnection,
) {
    constructor(
        endpoint: TerminalEndpoint,
        login: TerminalLogin,
        onPinHostKey: (String, String) -> Unit = { _, _ -> },
    ) : this(listOf(endpoint), login, onPinHostKey)

    init {
        require(routes.isNotEmpty()) { "a terminal needs at least one route" }
    }

    /** The route the shell is open on */
    @Volatile
    var connectedRoute: TerminalEndpoint? = null
        private set

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
            val connected = withContext(Dispatchers.IO) { connect() }
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

    /** Only the last route redials a silent hang-up */
    private fun connect(): TerminalConnection {
        val failures = mutableListOf<Pair<TerminalEndpoint, String>>()
        for ((index, route) in routes.withIndex()) {
            val error = try {
                return dial(route, login, onPinHostKey, index == routes.lastIndex).also { connectedRoute = route }
            } catch (failure: Exception) {
                failure
            }
            if (routes.size == 1 || !mayTryAnotherRoute(error)) throw described(error)
            failures += route to (error.message ?: error.toString())
        }
        throw TerminalRoutesFailed(failures)
    }

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

    companion object {
        /** Whether the next route may try after this failure */
        fun mayTryAnotherRoute(error: Throwable): Boolean {
            val chain = generateSequence(error) { it.cause }.take(6).toList()
            if (chain.any { it is ServerControlError.HostKeyMismatch || it is UserAuthException }) return false
            return when (error) {
                is kotlinx.coroutines.CancellationException -> false
                is ServerControlError.ConnectionFailed, is ServerControlError.Timeout -> true
                is ServerControlError -> false
                else -> chain.any { it is java.io.IOException }
            }
        }

        /** The app's own error, even when sshj wrapped it */
        private fun described(error: Exception): Exception =
            generateSequence<Throwable>(error) { it.cause }.take(6).filterIsInstance<ServerControlError>().firstOrNull()
                ?: ServerControlError.ConnectionFailed(error.toString())
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
    redial: Boolean = true,
): TerminalConnection {
    val pauses = if (redial) SSHClients.REDIAL_PAUSES_MS else emptyList()
    val timeout = endpoint.connectTimeoutMs
    val hops = endpoint.hops
    val first = hops.firstOrNull()
        ?: return TerminalConnection(
            SSHClients.redialing(pauses) {
                dialDirect(endpoint.host, endpoint.port, endpoint.pinnedHostKey, login, onPinHostKey, timeout)
            },
        )

    val chain = mutableListOf(
        SSHClients.redialing(pauses) {
            dialDirect(first.host, first.port, first.pinnedHostKey, first.login, onPinHostKey, timeout)
        },
    )
    val far = runCatching {
        for (hop in hops.drop(1)) {
            chain += dialDirect(hop.host, hop.port, hop.pinnedHostKey, hop.login, onPinHostKey, timeout, via = chain.last())
        }
        dialDirect(endpoint.host, endpoint.port, endpoint.pinnedHostKey, login, onPinHostKey, timeout, via = chain.last())
    }.getOrElse { failure ->
        chain.reversed().forEach { runCatching { it.disconnect() } }
        throw failure
    }
    return TerminalConnection(far, chain.reversed().map { client -> AutoCloseable { client.disconnect() } })
}

private fun dialDirect(
    host: String,
    port: Int,
    pin: String?,
    login: TerminalLogin,
    onPinHostKey: (String, String) -> Unit,
    timeoutMs: Int,
    via: SSHClient? = null,
): SSHClient {
    val client = SSHClients.create(timeoutMs)
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
