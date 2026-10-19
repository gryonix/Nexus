package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.core.DNSPublishOutcome
import com.skaymer.gryonixnexus.core.DNSPublishingProvider
import com.skaymer.gryonixnexus.core.DNSRecord
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class ServiceDNSPublisherTests {
    private fun server(scope: DeploymentScope = DeploymentScope.PUBLIC_INTERNET, host: String = "203.0.113.40") =
        Deployment(
            id = "S-1",
            name = "pair",
            topology = Topology.SINGLE_HOST,
            domain = "example.test",
            additionalDomains = listOf("example.org"),
            entry = HostEndpoint(host = host, user = "root"),
            services = setOf(ServiceID.VAULTWARDEN),
            scope = scope,
        )

    private class Recording : DNSPublishingProvider {
        val zones = mutableMapOf<String, List<DNSRecord>>()
        override val displayName = "Recording"
        override suspend fun verifyToken() {}
        override suspend fun apply(records: List<DNSRecord>, zone: String) {}
        override suspend fun publishReportingOutcomes(records: List<DNSRecord>, zone: String): List<DNSPublishOutcome> {
            zones[zone] = records
            return records.map { DNSPublishOutcome(it, DNSPublishOutcome.Result.Created) }
        }
    }

    private val text = ServiceDNSPublisher.Text(
        point = { "point $it" }, manual = { "manual $it" }, done = { "done $it" }, failed = { z, n -> "failed $z $n" },
    )
    private val vault = ServiceRegistry.all.first { it.id == ServiceID.VAULTWARDEN }

    @Test
    fun `an added service gets an A record on every domain, each in its own zone`() = runTest {
        val provider = Recording()
        val lines = ServiceDNSPublisher({ provider }, text, { emptyList() }).publish(vault, server())
        assertEquals(listOf("done example.test", "done example.org"), lines)
        assertEquals(listOf("vault.example.test"), provider.zones["example.test"]?.map { it.name })
        assertEquals(listOf("vault.example.org"), provider.zones["example.org"]?.map { it.name })
        assertTrue(provider.zones.values.flatten().all { it.value == "203.0.113.40" && it.type == DNSRecord.RecordType.A })
    }

    @Test
    fun `a name that already points at another machine is left alone and said so`() = runTest {
        val provider = Recording()
        val text = ServiceDNSPublisher.Text(
            point = { "point $it" }, manual = { "manual $it" }, done = { "done $it" }, failed = { z, n -> "failed $z $n" },
            elsewhere = { name, address -> "kept $name at $address" },
        )
        val lines = ServiceDNSPublisher({ provider }, text) { name ->
            if (name == "vault.example.test") listOf("198.51.100.9") else emptyList()
        }.publish(vault, server())
        assertEquals(listOf("done example.org", "kept vault.example.test at 198.51.100.9"), lines)
        assertEquals(null, provider.zones["example.test"])
        assertEquals(listOf("vault.example.org"), provider.zones["example.org"]?.map { it.name })
    }

    @Test
    fun `a name that already points here is published as before`() = runTest {
        val provider = Recording()
        val lines = ServiceDNSPublisher({ provider }, text) { listOf("203.0.113.40") }.publish(vault, server())
        assertEquals(listOf("done example.test", "done example.org"), lines)
    }

    @Test
    fun `without a token it says which records to add, and a local server adds none`() = runTest {
        val manual = ServiceDNSPublisher({ null }, text, { emptyList() }).publish(vault, server())
        assertEquals(listOf("manual vault.example.test A 203.0.113.40, vault.example.org A 203.0.113.40"), manual)
        assertEquals(emptyList(), ServiceDNSPublisher({ Recording() }, text, { emptyList() }).publish(vault, server(DeploymentScope.LOCAL_ONLY)))
        assertEquals(listOf("point vault.example.test, vault.example.org"),
            ServiceDNSPublisher({ Recording() }, text, { emptyList() }).publish(vault, server(host = "vps.example.test")))
    }

    @Test
    fun `a server entered by name gets records on the address that name has`() = runTest {
        val provider = Recording()
        val lines = ServiceDNSPublisher({ provider }, text) { name ->
            if (name == "vps.example.test") listOf("203.0.113.50") else emptyList()
        }.publish(vault, server(host = "vps.example.test"))
        assertEquals(listOf("done example.test", "done example.org"), lines)
        assertTrue(provider.zones.values.flatten().all { it.value == "203.0.113.50" })
    }

    @Test
    fun `an added service without its records asks to add them, and asks nothing once they are in place`() = runTest {
        val (update, notes) = ServiceDNSPublisher({ Recording() }, text, { emptyList() }).pendingAdd(vault, server())
        assertEquals(listOf("vault.example.test", "vault.example.org"), update?.add)
        assertEquals(emptyList(), notes)
        val (none, _) = ServiceDNSPublisher({ Recording() }, text, { listOf("203.0.113.40") }).pendingAdd(vault, server())
        assertEquals(null, none)
    }

    @Test
    fun `a removed service asks to remove the records that still point here`() = runTest {
        val after = server().copy(services = emptySet())
        val update = ServiceDNSPublisher({ Recording() }, text, { listOf("203.0.113.40") }).pendingRemove(vault, server(), after)
        assertEquals(listOf("vault.example.test", "vault.example.org"), update?.remove)
        assertEquals(null, ServiceDNSPublisher({ Recording() }, text, { emptyList() }).pendingRemove(vault, server(), after))
    }
}
