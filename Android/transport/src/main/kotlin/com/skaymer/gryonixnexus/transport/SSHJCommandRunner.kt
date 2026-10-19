package com.skaymer.gryonixnexus.transport

import com.skaymer.gryonixnexus.servercontrol.ExecChunk
import com.skaymer.gryonixnexus.servercontrol.ExecResult
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.ServerControlError
import java.io.InputStream
import java.io.InputStreamReader
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.channels.trySendBlocking
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runInterruptible
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import net.schmizz.sshj.SSHClient
import net.schmizz.sshj.connection.channel.direct.Session
import net.schmizz.sshj.common.KeyType
import net.schmizz.sshj.transport.verification.HostKeyVerifier
import net.schmizz.sshj.userauth.keyprovider.KeyProvider
import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters

class SSHJCommandRunner(
    private val settings: SSHConnectionSettings,
    private val onPinHostKey: (SSHHostID, String) -> Unit = { _, _ -> },
    private val connect: suspend (SSHConnectionSettings.Route.Address, SSHHostID) -> SSHClient =
        ::defaultConnect,
) : SSHCommandRunner {
    private val clients = ConcurrentHashMap<SSHHostID, SSHClient>()
    private val lock = Mutex()

    private val channels = Semaphore(MAX_CONCURRENT_CHANNELS)

    override suspend fun run(command: String, host: SSHHostID, timeout: Duration): ExecResult =
        execute(command, null, host, timeout)

    override suspend fun run(
        command: String,
        secret: String,
        host: SSHHostID,
        timeout: Duration,
    ): ExecResult = execute(command, secret.toByteArray(Charsets.UTF_8), host, timeout)

    private suspend fun execute(
        command: String,
        stdin: ByteArray?,
        host: SSHHostID,
        timeout: Duration,
    ): ExecResult = channels.withPermit {
        withSession(host, command, timeout) { exec ->
            val out = drain(exec.inputStream)
            val err = drain(exec.errorStream)
            exec.outputStream.use { remoteStdin -> stdin?.let { remoteStdin.write(it) } }
            val stdout = out.get()
            val stderr = err.get()
            exec.join()
            ExecResult(exitCode = exec.exitStatus, stdout = stdout, stderr = stderr)
        }
    }

    /** Streaming exec: chunks arrive as the remote produces them */
    override fun stream(command: String, host: SSHHostID, timeout: Duration): Flow<ExecChunk> =
        channelFlow {
            channels.withPermit {
                withSession(host, command, timeout) { exec ->
                    runCatching { exec.outputStream.close() }
                    val readers = listOf(
                        pump(exec.inputStream) { trySendBlocking(ExecChunk.Stdout(it)).isSuccess },
                        pump(exec.errorStream) { trySendBlocking(ExecChunk.Stderr(it)).isSuccess },
                    )
                    readers.forEach { it.join() }
                    exec.join()
                }
            }
        }

    /** Sends a command without awaiting its exit status */
    override suspend fun fireAndForget(command: String, host: SSHHostID) {
        channels.withPermit {
            withContext(Dispatchers.IO) {
                val session = client(host).startSession()
                runCatching { session.exec(command) }
                runCatching { session.close() }
            }
        }
    }

    override suspend fun disconnect() {
        lock.withLock {
            clients.values.forEach { runCatching { it.disconnect() } }
            clients.clear()
        }
    }

    suspend fun sshClient(host: SSHHostID): SSHClient = client(host)

    // --------------------------------------------------------------- Sessions

    /** Runs [body] on one channel; timeouts close only it */
    private suspend fun <T> withSession(
        host: SSHHostID,
        command: String,
        timeout: Duration,
        body: (Session.Command) -> T,
    ): T {
        val client = client(host)
        val session = withContext(Dispatchers.IO) { client.startSession() }
        val timedOut = AtomicBoolean(false)
        return try {
            coroutineScope {
                val exec = runInterruptible(Dispatchers.IO) { session.exec(command) }
                val watchdog = launch { expire(host, exec, timeout, timedOut) }
                try {
                    runInterruptible(Dispatchers.IO) { body(exec) }
                } finally {
                    watchdog.cancel()
                }
            }.also { if (timedOut.get()) throw ServerControlError.Timeout(command) }
        } catch (failure: Exception) {
            if (timedOut.get()) throw ServerControlError.Timeout(command)
            throw failure
        } finally {
            withContext(NonCancellable + Dispatchers.IO) { runCatching { session.close() } }
        }
    }

    /** Closes the channel at the deadline, else the link */
    private suspend fun expire(
        host: SSHHostID,
        exec: Session.Command,
        timeout: Duration,
        timedOut: AtomicBoolean,
    ) {
        delay(timeout)
        timedOut.set(true)
        withContext(Dispatchers.IO) { runCatching { exec.close() } }
        delay(CLOSE_GRACE)
        drop(host)
    }

    private suspend fun client(host: SSHHostID): SSHClient {
        clients[host]?.let { if (it.isConnected) return it else drop(host) }
        return lock.withLock {
            clients[host]?.let { if (it.isConnected) return@withLock it }
            val route = settings.route(host)
                ?: throw ServerControlError.NotConfigured("no address for $host")
            val client = connect(route.address, host)
            clients[host] = client
            client
        }
    }

    private suspend fun drop(host: SSHHostID) {
        lock.withLock { clients.remove(host)?.let { runCatching { it.disconnect() } } }
    }

    private fun drain(source: InputStream): java.util.concurrent.Future<String> {
        val result = java.util.concurrent.CompletableFuture<String>()
        Thread {
            result.complete(
                runCatching { source.readBytes().decodeToString() }.getOrDefault(""),
            )
        }.apply { isDaemon = true; start() }
        return result
    }

    /** Reads text as it arrives; stops when [deliver] is refused */
    private fun pump(source: InputStream, deliver: (String) -> Boolean): Thread = Thread {
        val reader = InputStreamReader(source, Charsets.UTF_8)
        val buffer = CharArray(8 * 1024)
        while (true) {
            val read = try { reader.read(buffer) } catch (_: Exception) { -1 }
            if (read <= 0 || !deliver(String(buffer, 0, read))) break
        }
    }.apply { isDaemon = true; start() }

    companion object {
        const val MAX_CONCURRENT_CHANNELS = 4
        private val CLOSE_GRACE = 5.seconds

        /** A connected, authenticated client for one address */
        internal suspend fun defaultConnect(
            address: SSHConnectionSettings.Route.Address,
            host: SSHHostID,
        ): SSHClient = error("a runner built without a connector cannot dial $host at ${address.host}")

        /** Authenticates [client], already connected, the way [host] requires */
        fun authenticate(
            client: SSHClient,
            settings: SSHConnectionSettings,
            host: SSHHostID,
        ) {
            val username = settings.username(host)
            val password = settings.passwords[host]
            if (password != null) {
                client.authPassword(username, password)
            } else {
                client.authPublickey(username, keyProvider(settings.privateKeySeed))
            }
        }

        /** The app's ed25519 identity as sshj wants it */
        fun keyProvider(seed: ByteArray): KeyProvider =
            object : KeyProvider {
                private val pair = ed25519(seed)
                override fun getPrivate() = pair.private
                override fun getPublic() = pair.public
                override fun getType() = KeyType.ED25519
            }

        private fun ed25519(seed: ByteArray): java.security.KeyPair {
            require(seed.size == AppSSHKeyGenerator.SEED_LENGTH) {
                "an ed25519 seed is ${AppSSHKeyGenerator.SEED_LENGTH} bytes, got ${seed.size}"
            }
            val parameters = Ed25519PrivateKeyParameters(seed, 0)
            val factory = java.security.KeyFactory.getInstance("Ed25519")
            val privateInfo = org.bouncycastle.crypto.util.PrivateKeyInfoFactory
                .createPrivateKeyInfo(parameters)
            val publicInfo = org.bouncycastle.crypto.util.SubjectPublicKeyInfoFactory
                .createSubjectPublicKeyInfo(parameters.generatePublicKey())
            return java.security.KeyPair(
                factory.generatePublic(java.security.spec.X509EncodedKeySpec(publicInfo.encoded)),
                factory.generatePrivate(java.security.spec.PKCS8EncodedKeySpec(privateInfo.encoded)),
            )
        }

        fun verifier(
            address: SSHConnectionSettings.Route.Address,
            host: SSHHostID,
            onPin: (SSHHostID, String) -> Unit,
        ): HostKeyVerifier = TOFUHostKeyVerifier(address.host, address.pin) { presented ->
            onPin(host, presented)
        }
    }
}
