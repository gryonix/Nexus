package com.skaymer.gryonixnexus.app.secrets

import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import kotlin.test.assertEquals
import kotlin.test.assertNull
import org.junit.jupiter.api.Test

class KnownHostsStoreTests {
    private val deployment = Deployment(
        id = "S-1", name = "orion", topology = Topology.SINGLE_HOST, domain = "example.net",
        entry = HostEndpoint(host = "203.0.113.5", user = "root"), services = emptySet(),
    )
    private val secrets = InMemorySecretStore()
    private val known = KnownHostsStore(secrets)
    private val key = "ssh-ed25519 aGVsbG8="

    @Test
    fun `a pinned machine is listed and forgetting it removes the pin`() {
        val node = deployment.nodes.first()
        DeploymentSecrets(secrets, deployment.id).setHostKeyPin(key, node.id)
        val rows = known.rows(listOf(deployment))
        assertEquals(1, rows.size)
        assertEquals("203.0.113.5:22", rows[0].endpoint)
        known.forget(rows[0], listOf(deployment))
        assertEquals(0, known.rows(listOf(deployment)).size)
        assertNull(DeploymentSecrets(secrets, deployment.id).hostKeyPin(node.id))
    }

    @Test
    fun `a jump host pin is listed by its endpoint and can be forgotten`() {
        DeploymentSecrets(secrets, deployment.id).setBastionHostKeyPin(key, "198.51.100.7:22")
        val rows = known.rows(listOf(deployment))
        assertEquals(listOf("198.51.100.7:22"), rows.map { it.endpoint })
        known.forget(rows[0], listOf(deployment))
        assertEquals(0, known.rows(listOf(deployment)).size)
    }
}
