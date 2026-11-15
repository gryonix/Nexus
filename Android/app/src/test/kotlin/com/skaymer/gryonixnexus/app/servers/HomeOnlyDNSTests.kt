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
import com.skaymer.gryonixnexus.servercontrol.PublicPortProbe
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class HomeOnlyDNSTests {
    private fun vault(removed: Set<ServiceID> = emptySet()) = Deployment(
        id = "S-1", name = "pair", topology = Topology.SINGLE_HOST, domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
        services = setOf(ServiceID.VAULTWARDEN), homeOnlyDNSRemoved = removed,
    )

    private class Recording : DNSPublishingProvider {
        val calls = mutableListOf<String>()
        override val displayName = "Recording"
        override suspend fun verifyToken() {}
        override suspend fun apply(records: List<DNSRecord>, zone: String) {}
        override suspend fun publishReportingOutcomes(records: List<DNSRecord>, zone: String): List<DNSPublishOutcome> {
            calls += "publish ${records.map { it.name }} $zone"
            return records.map { DNSPublishOutcome(it, DNSPublishOutcome.Result.Created) }
        }
        override suspend fun removeAddressRecords(names: List<String>, address: String, zone: String): List<String> {
            calls += "remove $names $address $zone"
            return names
        }
    }

    private val service = ServiceRegistry.all.first { it.id == ServiceID.VAULTWARDEN }

    @Test
    fun `removing calls the provider for the service name`() = runTest {
        val provider = Recording()
        val outcome = HomeOnlyDNS({ provider }, resolve = { emptyList() }).change(HomeOnlyDNS.Action.REMOVE, service, vault())
        assertTrue(outcome is HomeOnlyDNS.Outcome.Done)
        assertEquals(listOf("remove [vault.example.test] 203.0.113.40 example.test"), provider.calls)
    }

    @Test
    fun `restoring publishes the record again`() = runTest {
        val provider = Recording()
        val outcome = HomeOnlyDNS({ provider }, resolve = { emptyList() }).change(HomeOnlyDNS.Action.RESTORE, service, vault(setOf(ServiceID.VAULTWARDEN)))
        assertTrue(outcome is HomeOnlyDNS.Outcome.Done)
        assertEquals(listOf("publish [vault.example.test] example.test"), provider.calls)
    }

    @Test
    fun `without a token the records come back to change by hand`() = runTest {
        val outcome = HomeOnlyDNS({ null }, resolve = { emptyList() }).change(HomeOnlyDNS.Action.REMOVE, service, vault())
        val manual = (outcome as HomeOnlyDNS.Outcome.ByHand).manual
        assertEquals(listOf("vault.example.test A 203.0.113.40"), manual.lines)
    }

    @Test
    fun `a removed record is not published again by the sync`() = runTest {
        val text = ServiceDNSPublisher.Text(point = { it }, manual = { it }, done = { it }, failed = { z, _ -> z })
        val publisher = ServiceDNSPublisher({ Recording() }, text, { emptyList() })
        assertTrue(publisher.publish(service, vault(setOf(ServiceID.VAULTWARDEN))).isEmpty())
        assertNull(publisher.pendingAdd(service, vault(setOf(ServiceID.VAULTWARDEN))).first)
    }

    @Test
    fun `the controller keeps a verdict and clears it when the service opens up`() = runTest {
        val saved = mutableListOf<Deployment>()
        val guards = mutableListOf<Triple<String, Boolean, Int>>()
        val controller = HomeOnlyController(
            scope = this, persist = { saved += it }, reprovision = {},
            guardHost = { d, host, clearing -> guards += Triple(host, clearing, d.hostsRefusingVPN.size) },
            probe = { _, ports -> ports.filter { it == 25 } },
        )
        val mail = ServiceRegistry.all.first { it.id == ServiceID.DOCKER_MAILSERVER }
        val d = vault().copy(services = setOf(ServiceID.DOCKER_MAILSERVER), topology = Topology.VPS_RELAY_WITH_HOME_BACKEND, homeWGAddress = "10.8.0.2")
        controller.check(d, mail)
        assertTrue(controller.verdicts.value[ServiceID.DOCKER_MAILSERVER] is PublicPortProbe.Verdict.Open)
        controller.set(d.copy(homeOnlyServices = setOf(ServiceID.DOCKER_MAILSERVER)), mail, false)
        assertNull(controller.verdicts.value[ServiceID.DOCKER_MAILSERVER])
        assertEquals(emptySet(), saved.last().homeOnlyNoVPN)
    }

    @Test
    fun `a service with a site offers the switch on any server`() {
        assertTrue(HomeOnlyController.offers(vault(), service))
        assertTrue(HomeOnlyController.offers(vault().copy(scope = DeploymentScope.DYNAMIC_DNS), service))
    }

    @Test
    fun `a port sync that fails is kept for the row`() {
        val eager = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Unconfined)
        val controller = HomeOnlyController(
            scope = eager, persist = {}, reprovision = {}, guardHost = { _, _, _ -> },
            keepPortsHome = { _, _ -> error("link dropped") },
        )
        controller.set(vault().copy(scope = DeploymentScope.DYNAMIC_DNS), service, true)
        assertEquals(HomeOnlyController.Failure.Told("link dropped"), controller.failures.value[ServiceID.VAULTWARDEN])
    }
}
