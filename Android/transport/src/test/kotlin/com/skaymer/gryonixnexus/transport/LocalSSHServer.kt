package com.skaymer.gryonixnexus.transport

import java.io.OutputStream
import java.security.KeyPairGenerator
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import net.schmizz.sshj.SSHClient
import org.apache.sshd.common.keyprovider.KeyPairProvider
import org.apache.sshd.server.SshServer
import org.apache.sshd.server.channel.ChannelSession
import org.apache.sshd.server.command.Command
import org.apache.sshd.server.command.CommandFactory
import org.apache.sshd.server.session.ServerSession

class LocalSSHServer {
    /** What a scripted command does: stdout, stderr, exit code */
    class Reply(
        val stdout: String = "",
        val stderr: String = "",
        val exitCode: Int = 0,
        /** Milliseconds to take before finishing — for the timeout tests */
        val delayMillis: Long = 0,
        /** Writes what arrived on stdin back to stdout */
        val echoesStdin: Boolean = false,
    )

    private val server: SshServer = SshServer.setUpDefaultServer()
    private val scripted = ConcurrentHashMap<String, Reply>()
    private val seen = mutableListOf<String>()
    private val sessions = AtomicInteger(0)
    private val peakChannels = AtomicInteger(0)
    private val liveChannels = AtomicInteger(0)
    private val liveSessions = AtomicInteger(0)
    private val closedSessions = AtomicInteger(0)
    private val ptyColumns = AtomicInteger(0)

    val resizes: MutableList<Int> = java.util.concurrent.CopyOnWriteArrayList()

    val initialColumns: Int get() = ptyColumns.get()

    val commands: List<String> get() = synchronized(seen) { seen.toList() }

    val connectionCount: Int get() = sessions.get()

    /** How many of those are still connected */
    val liveConnectionCount: Int get() = liveSessions.get()

    val peakConcurrentChannels: Int get() = peakChannels.get()

    /** Every session that ended, signed in or not */
    val closedSessionCount: Int get() = closedSessions.get()

    val port: Int get() = server.port

    val hostKeyLine: String
        get() = TOFUHostKeyVerifier.openSSHString(server.keyPairProvider.loadKeys(null).first().public)

    var password: String? = null
    var authorizedKey: java.security.PublicKey? = null

    fun script(command: String, reply: Reply) {
        scripted[command] = reply
    }

    fun start(): LocalSSHServer {
        if (java.security.Security.getProvider("BC") == null) {
            java.security.Security.addProvider(
                org.bouncycastle.jce.provider.BouncyCastleProvider(),
            )
        }
        server.port = 0
        server.keyPairProvider = KeyPairProvider.wrap(
            KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair(),
        )
        server.setPasswordAuthenticator { _, offered, _ -> password != null && offered == password }
        server.setPublickeyAuthenticator { _, offered, _ ->
            val expected = authorizedKey
            expected != null && offered.encoded.contentEquals(expected.encoded)
        }
        server.addSessionListener(object : org.apache.sshd.common.session.SessionListener {
            override fun sessionEvent(
                session: org.apache.sshd.common.session.Session,
                event: org.apache.sshd.common.session.SessionListener.Event,
            ) {
                if (event == org.apache.sshd.common.session.SessionListener.Event.Authenticated) {
                    sessions.incrementAndGet()
                    liveSessions.incrementAndGet()
                }
            }

            override fun sessionClosed(session: org.apache.sshd.common.session.Session) {
                closedSessions.incrementAndGet()
                if (session.isAuthenticated || session.username != null) {
                    liveSessions.updateAndGet { if (it > 0) it - 1 else 0 }
                }
            }
        })
        server.commandFactory = CommandFactory { _, command -> ScriptedCommand(command) }
        server.shellFactory = org.apache.sshd.server.shell.ShellFactory { _ -> EchoShell() }
        server.forwardingFilter = org.apache.sshd.server.forward.AcceptAllForwardingFilter.INSTANCE
        server.start()
        return this
    }

    fun stop() = server.stop(true)

    /** A shell that echoes and announces its window size */
    private inner class EchoShell : Command {
        private lateinit var input: java.io.InputStream
        private lateinit var out: OutputStream
        private var exit: org.apache.sshd.server.ExitCallback? = null
        @Volatile private var environment: org.apache.sshd.server.Environment? = null

        override fun setInputStream(inputStream: java.io.InputStream) { input = inputStream }
        override fun setOutputStream(output: OutputStream) { out = output }
        override fun setErrorStream(output: OutputStream) = Unit
        override fun setExitCallback(callback: org.apache.sshd.server.ExitCallback) { exit = callback }

        override fun start(channel: ChannelSession, env: org.apache.sshd.server.Environment) {
            environment = env
            ptyColumns.set(env.ptyModes.let { _ ->
                env.env["COLUMNS"]?.toIntOrNull() ?: 0
            })
            env.addSignalListener({ _, _ ->
                resizes.add(env.env["COLUMNS"]?.toIntOrNull() ?: -1)
            }, org.apache.sshd.server.Signal.WINCH)
            out.write("ready\n".toByteArray()); out.flush()
            Thread {
                val buffer = ByteArray(1024)
                while (true) {
                    val read = try { input.read(buffer) } catch (_: Exception) { -1 }
                    if (read <= 0) break
                    if (String(buffer, 0, read).contains("exit")) break
                    out.write(buffer, 0, read); out.flush()
                }
                exit?.onExit(0)
            }.apply { isDaemon = true }.start()
        }

        override fun destroy(channel: ChannelSession) = Unit
    }

    private inner class ScriptedCommand(private val command: String) : Command {
        private lateinit var out: OutputStream
        private lateinit var err: OutputStream
        private var exit: org.apache.sshd.server.ExitCallback? = null

        private var input: java.io.InputStream? = null

        override fun setInputStream(input: java.io.InputStream) { this.input = input }
        override fun setOutputStream(output: OutputStream) { out = output }
        override fun setErrorStream(output: OutputStream) { err = output }
        override fun setExitCallback(callback: org.apache.sshd.server.ExitCallback) {
            exit = callback
        }

        override fun start(channel: ChannelSession, env: org.apache.sshd.server.Environment) {
            synchronized(seen) { seen += command }
            val now = liveChannels.incrementAndGet()
            peakChannels.updateAndGet { maxOf(it, now) }
            Thread {
                val reply = scripted[command]
                    ?: Reply(stderr = "sh: $command: not found\n", exitCode = 127)
                if (reply.delayMillis > 0) Thread.sleep(reply.delayMillis)
                if (reply.echoesStdin) input?.readBytes()?.let { out.write(it) }
                out.write(reply.stdout.toByteArray()); out.flush()
                err.write(reply.stderr.toByteArray()); err.flush()
                liveChannels.decrementAndGet()
                exit?.onExit(reply.exitCode)
            }.apply { isDaemon = true }.start()
        }

        override fun destroy(channel: ChannelSession) = Unit
    }

    /** A client connected and authenticated against this server */
    fun client(settings: SSHConnectionSettings, host: com.skaymer.gryonixnexus.servercontrol.SSHHostID): SSHClient {
        val client = SSHClient()
        client.addHostKeyVerifier(
            object : net.schmizz.sshj.transport.verification.HostKeyVerifier {
                override fun verify(hostname: String, port: Int, key: java.security.PublicKey) = true
                override fun findExistingAlgorithms(hostname: String, port: Int) = emptyList<String>()
            },
        )
        client.connect("127.0.0.1", port)
        SSHJCommandRunner.authenticate(client, settings, host)
        return client
    }
}
