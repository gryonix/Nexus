package com.skaymer.gryonixnexus.app.session

import com.skaymer.gryonixnexus.app.secrets.DeploymentSecrets
import com.skaymer.gryonixnexus.app.secrets.InMemorySecretStore
import com.skaymer.gryonixnexus.app.servers.ProxyStore
import com.skaymer.gryonixnexus.app.servers.ServerAccessStore
import com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.BastionHop
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.FallbackAddress
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.ProxyProfile
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.ServerAccessOptions
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.Test

/** The dial itself, against real SSH daemons */
class ServerSessionsLiveTests {
    private val seed = System.getenv("GRYONIXNEXUS_LAB_SEED")
    private val target = System.getenv("GRYONIXNEXUS_LAB_TARGET") ?: "127.0.0.1:2201"
    private val jumped = System.getenv("GRYONIXNEXUS_LAB_JUMPED") ?: "gx-target:22"
    private val bastion = System.getenv("GRYONIXNEXUS_LAB_BASTION") ?: "127.0.0.1:2202"
    private val socks = System.getenv("GRYONIXNEXUS_LAB_SOCKS") ?: "127.0.0.1:1080"
    private val httpProxy = System.getenv("GRYONIXNEXUS_LAB_HTTP") ?: "127.0.0.1:3128"

    private val secrets = InMemorySecretStore()
    private val settings = InMemorySettingsStore()

    private fun endpoint(spec: String, user: String = "root"): HostEndpoint {
        val (host, port) = spec.split(":", limit = 2)
        return HostEndpoint(host = host, port = port.toInt(), user = user)
    }

    private fun server(spec: String, id: String = "LAB-1") = Deployment(
        id = id,
        name = "lab",
        topology = Topology.SINGLE_HOST,
        domain = "lab.test",
        entry = endpoint(spec),
    ).also { DeploymentSecrets(secrets, it.id).setIdentitySeed(seed!!.hexToByteArray()) }

    private fun sessions() = ServerSessions(secrets, settings, fleet = { emptyList() })

    private suspend fun hostname(deployment: Deployment, sessions: ServerSessions): String {
        val result = sessions.runner(deployment).run("hostname", SSHHostID.VPS, 20.seconds)
        return result.stdout.trim()
    }

    private fun requireLab() = assumeTrue(!seed.isNullOrEmpty(), "the live lab is not up")

    @Test
    fun `a server is reached at its own address`() = runBlocking {
        requireLab()
        assertEquals("target2", hostname(server(target), sessions()))
    }

    @Test
    fun `a machine with no route of its own is reached through the bastion`() = runBlocking {
        requireLab()
        val deployment = server(jumped)
        ServerAccessStore.save(
            settings, deployment.id,
            ServerAccessOptions(bastion = BastionHop(manual = endpoint(bastion))),
        )
        assertEquals("target", hostname(deployment, sessions()))
    }

    @Test
    fun `a silent address falls over to the second one`() = runBlocking {
        requireLab()
        val deployment = server("127.0.0.1:2299")
        ServerAccessStore.save(
            settings, deployment.id,
            ServerAccessOptions(fallback = FallbackAddress(host = "127.0.0.1", port = endpoint(target).port)),
        )
        val sessions = sessions()
        assertEquals("target2", hostname(deployment, sessions))
        assertTrue(deployment.id in sessions.onFallback.value, "the screen would not have said so")
    }

    @Test
    fun `a refused key is not retried at the second address`() = runBlocking {
        requireLab()
        val deployment = server(target)
        DeploymentSecrets(secrets, deployment.id).setIdentitySeed(ByteArray(32) { 7 })
        ServerAccessStore.save(
            settings, deployment.id,
            ServerAccessOptions(fallback = FallbackAddress(host = "127.0.0.1", port = 2203)),
        )
        val failure = runCatching { hostname(deployment, sessions()) }
        assertTrue(failure.isFailure, "the key was refused here and accepted there: ${failure.getOrNull()}")
    }

    @Test
    fun `a server is reached through a SOCKS5 proxy`() = runBlocking {
        requireLab()
        val deployment = server(target)
        val proxy = ProxyProfile(id = "P-1", name = "lab socks", kind = ProxyProfile.Kind.SOCKS5,
                                 host = endpoint(socks).host, port = endpoint(socks).port)
        ProxyStore.save(settings, listOf(proxy))
        ServerAccessStore.save(settings, deployment.id, ServerAccessOptions(proxyID = proxy.id))
        assertEquals("target2", hostname(deployment, sessions()))
    }

    @Test
    fun `a server is reached through an HTTP CONNECT proxy`() = runBlocking {
        requireLab()
        val deployment = server(target)
        val proxy = ProxyProfile(id = "P-2", name = "lab http", kind = ProxyProfile.Kind.HTTP_CONNECT,
                                 host = endpoint(httpProxy).host, port = endpoint(httpProxy).port)
        ProxyStore.save(settings, listOf(proxy))
        ServerAccessStore.save(settings, deployment.id, ServerAccessOptions(proxyID = proxy.id))
        assertEquals("target2", hostname(deployment, sessions()))
    }

    @Test
    fun `a bastion is dialled through the proxy as well`() = runBlocking {
        requireLab()
        val deployment = server(jumped)
        val proxy = ProxyProfile(id = "P-3", name = "lab socks", kind = ProxyProfile.Kind.SOCKS5,
                                 host = endpoint(socks).host, port = endpoint(socks).port)
        ProxyStore.save(settings, listOf(proxy))
        ServerAccessStore.save(
            settings, deployment.id,
            ServerAccessOptions(bastion = BastionHop(manual = endpoint(bastion)), proxyID = proxy.id),
        )
        assertEquals("target", hostname(deployment, sessions()))
    }
}
