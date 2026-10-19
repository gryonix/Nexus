package com.skaymer.gryonixnexus.app.configurator

import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.core.DistributionProfileID
import com.skaymer.gryonixnexus.core.ServerRole
import com.skaymer.gryonixnexus.core.ValidationError
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class ConfiguratorFormTests {
    private fun form(
        topology: Topology = Topology.SINGLE_HOST,
        domain: String = "example.com",
        publicIP: String = "203.0.113.10"
    ) = ConfiguratorForm(topology = topology, domain = domain, publicIP = publicIP)

    /** The mail host is DERIVED */
    @Test
    fun `the mail hostname is derived from the domain`() {
        assertEquals("mail.example.com", form().toInput().hostname)
        assertEquals("mail.other.test", form(domain = "other.test").toInput().hostname)
    }

    @Test
    fun `an empty reverse dns field means the default and not an empty name`() {
        assertNull(form().toInput().reverseDNSHostname)
        assertNull(form().copy(reverseDNSHostname = "   ").toInput().reverseDNSHostname)
        assertEquals(
            "relay.example.com",
            form().copy(reverseDNSHostname = "  relay.example.com  ").toInput().reverseDNSHostname
        )
    }

    /** A blank row is dropped, not parsed */
    @Test
    fun `blank additional domains are dropped rather than refused`() {
        val input = form().copy(
            additionalDomains = listOf("  Second.TEST ", "", "   ", "Third.test")
        ).toInput()
        assertEquals(listOf("second.test", "third.test"), input.additionalDomains.map { it.name })
    }

    @Test
    fun `a single host is one node carrying the public address`() {
        val nodes = form().serverNodes()
        assertEquals(1, nodes.size)
        assertEquals(ServerRole.SINGLE_HOST, nodes[0].role)
        assertEquals("203.0.113.10", nodes[0].publicAddress?.value)
        assertNull(nodes[0].vpnAddress)
    }

    /** Scenario B carries TWO distributions */
    @Test
    fun `a relay pair is two nodes each with its own distribution`() {
        val nodes = form(topology = Topology.VPS_RELAY_WITH_HOME_BACKEND).copy(
            distribution = DistributionProfileID.UBUNTU,
            homeDistribution = DistributionProfileID.DEBIAN
        ).serverNodes()

        assertEquals(2, nodes.size)
        assertEquals(ServerRole.VPS_RELAY, nodes[0].role)
        assertEquals(DistributionProfileID.UBUNTU, nodes[0].distribution)
        assertEquals("10.8.0.1", nodes[0].vpnAddress?.value)

        assertEquals(ServerRole.HOME_BACKEND, nodes[1].role)
        assertEquals(DistributionProfileID.DEBIAN, nodes[1].distribution)
        assertEquals("10.8.0.2", nodes[1].vpnAddress?.value)
        assertNull(nodes[1].publicAddress, "the home half has no public address to speak of")
    }

    @Test
    fun `local only accepts a name where the public path demands a domain`() {
        val local = form(domain = "orion.local", publicIP = "orion.local")
            .copy(scope = DeploymentScope.LOCAL_ONLY)
        assertEquals("orion.local", local.toInput().domain.name)
        assertEquals("orion.local", local.serverNodes()[0].publicAddress?.value)

        assertFailsWith<ValidationError> {
            form(domain = "example.com", publicIP = "orion.local").serverNodes()
        }
    }

    @Test
    fun `a malformed address is refused`() {
        assertFailsWith<ValidationError> { form(publicIP = "999.1.1.1").serverNodes() }
        assertFailsWith<ValidationError> { form(domain = "not a domain").toInput() }
    }

    @Test
    fun `the selected services are carried through unchanged`() {
        val services = setOf(ServiceID.NEXTCLOUD, ServiceID.VAULTWARDEN)
        assertEquals(services, form().copy(services = services).toInput().services)
        assertTrue(form().toInput().services.isEmpty(), "an empty form installs nothing by itself")
    }
}
