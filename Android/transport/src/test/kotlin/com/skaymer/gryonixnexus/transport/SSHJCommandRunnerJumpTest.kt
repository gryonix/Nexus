package com.skaymer.gryonixnexus.transport

import com.skaymer.gryonixnexus.servercontrol.HomePathChoice
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.ServerControlError
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.runBlocking
import net.schmizz.sshj.SSHClient
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

private object TrustAll : net.schmizz.sshj.transport.verification.HostKeyVerifier {
    override fun verify(hostname: String, port: Int, key: java.security.PublicKey) = true
    override fun findExistingAlgorithms(hostname: String, port: Int) = emptyList<String>()
}

/** A machine behind the VPS is reached through it */
class SSHJCommandRunnerJumpTest {
    private lateinit var server: LocalSSHServer
    private val seed = ByteArray(32) { it.toByte() }

    private fun settings(homeLAN: String? = null, path: HomePathChoice = HomePathChoice.AUTOMATIC) = SSHConnectionSettings(
        vpsHost = "127.0.0.1",
        vpsPort = server.port,
        username = "owner",
        homeHost = "127.0.0.1",
        homePort = server.port,
        homeLANHost = homeLAN,
        homePath = path,
        privateKeySeed = seed,
    )

    @BeforeEach
    fun startServer() {
        server = LocalSSHServer().apply {
            authorizedKey = SSHJCommandRunner.keyProvider(seed).public
            start()
        }
        server.script("hostname", LocalSSHServer.Reply(stdout = "home\n"))
    }

    @AfterEach
    fun stopServer() {
        server.stop()
    }

    @Test
    fun `the home machine is dialled through the VPS session`() = runBlocking {
        val settings = settings()
        val parents = mutableListOf<SSHClient>()
        val runner = SSHJCommandRunner(
            settings,
            connectThrough = { address, host, through ->
                parents += through
                SSHClient().apply {
                    addHostKeyVerifier(TrustAll)
                    connectVia(through.newDirectConnection(address.host, address.port))
                    SSHJCommandRunner.authenticate(this, settings, host)
                }
            },
            connect = { _, host -> server.client(settings, host) },
        )
        val result = runner.run("hostname", SSHHostID.HOME, 10.seconds)
        assertEquals("home\n", result.stdout)
        assertEquals(1, parents.size)
        runner.disconnect()
    }

    @Test
    fun `the local network is used when it answers, without the VPS`() = runBlocking {
        val settings = settings(homeLAN = "127.0.0.1")
        var jumped = false
        val runner = SSHJCommandRunner(
            settings,
            connectThrough = { _, _, _ -> jumped = true; throw java.net.ConnectException("not expected") },
            connect = { _, host -> server.client(settings, host) },
        )
        val result = runner.run("hostname", SSHHostID.HOME, 10.seconds)
        assertEquals("home\n", result.stdout)
        assertTrue(!jumped)
        runner.disconnect()
    }

    @Test
    fun `away from home the VPS carries the link`() = runBlocking {
        val settings = settings(homeLAN = "192.0.2.1")
        var jumped = false
        val runner = SSHJCommandRunner(
            settings,
            connectThrough = { address, host, through ->
                jumped = true
                SSHClient().apply {
                    addHostKeyVerifier(TrustAll)
                    connectVia(through.newDirectConnection(address.host, address.port))
                    SSHJCommandRunner.authenticate(this, settings, host)
                }
            },
            connect = { _, host -> server.client(settings, host) },
            answers = { false },
        )
        val result = runner.run("hostname", SSHHostID.HOME, 10.seconds)
        assertEquals("home\n", result.stdout)
        assertTrue(jumped)
        runner.disconnect()
    }

    @Test
    fun `through the VPS the local network is not even probed`() = runBlocking {
        val settings = settings(homeLAN = "127.0.0.1", path = HomePathChoice.THROUGH_VPS)
        var probed = false
        var jumped = false
        val runner = SSHJCommandRunner(
            settings,
            connectThrough = { address, host, through ->
                jumped = true
                SSHClient().apply {
                    addHostKeyVerifier(TrustAll)
                    connectVia(through.newDirectConnection(address.host, address.port))
                    SSHJCommandRunner.authenticate(this, settings, host)
                }
            },
            connect = { _, host -> server.client(settings, host) },
            answers = { probed = true; true },
        )
        runner.run("hostname", SSHHostID.HOME, 10.seconds)
        assertTrue(jumped)
        assertTrue(!probed)
        runner.disconnect()
    }

    @Test
    fun `over the local network the VPS is never used`() = runBlocking {
        val settings = settings(homeLAN = "127.0.0.1", path = HomePathChoice.LOCAL_NETWORK)
        var jumped = false
        val runner = SSHJCommandRunner(
            settings,
            connectThrough = { _, _, _ -> jumped = true; throw java.net.ConnectException("not expected") },
            connect = { _, host -> server.client(settings, host) },
        )
        assertEquals("home\n", runner.run("hostname", SSHHostID.HOME, 10.seconds).stdout)
        assertTrue(!jumped)
        runner.disconnect()
    }

    @Test
    fun `over the local network a silent machine is an error, not a detour`() = runBlocking {
        val settings = settings(homeLAN = "192.0.2.1", path = HomePathChoice.LOCAL_NETWORK)
        val runner = SSHJCommandRunner(
            settings,
            connectThrough = { _, _, _ -> throw java.net.ConnectException("not expected") },
            connect = { _, _ -> throw java.net.ConnectException("down") },
        )
        val failure = runCatching { runner.run("hostname", SSHHostID.HOME, 10.seconds) }.exceptionOrNull()
        assertTrue(failure is ServerControlError.ConnectionFailed || failure is java.net.ConnectException, "got $failure")
        runner.disconnect()
    }
}
