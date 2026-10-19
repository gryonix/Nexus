package com.skaymer.gryonixnexus.app.configurator

import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.Topology
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class WizardStepTests {
    private fun form(
        scope: DeploymentScope = DeploymentScope.PUBLIC_INTERNET,
        services: Set<com.skaymer.gryonixnexus.catalog.ServiceID> = emptySet(),
        topology: Topology = Topology.SINGLE_HOST,
    ) = ConfiguratorForm(topology = topology, scope = scope, services = services)

    @Test
    fun `the plainest deployment asks four questions`() {
        assertEquals(
            listOf(WizardStep.SERVICES, WizardStep.DOMAIN, WizardStep.ADDRESS, WizardStep.DNS, WizardStep.REVIEW),
            wizardSteps(form()),
        )
    }

    @Test
    fun `a local-only server is never asked for a domain`() {
        val steps = wizardSteps(form(scope = DeploymentScope.LOCAL_ONLY))
        assertFalse(WizardStep.DOMAIN in steps, "$steps")
        assertTrue(WizardStep.ADDRESS in steps, "$steps")
    }

    @Test
    fun `a tunnelled deployment gets no records-to-paste step`() {
        assertFalse(WizardStep.DNS in wizardSteps(form(scope = DeploymentScope.CLOUDFLARE_TUNNEL)))
    }

    @Test
    fun `a mesh-only deployment gets no records-to-paste step`() {
        assertFalse(WizardStep.DNS in wizardSteps(form(scope = DeploymentScope.MESH_ONLY)))
    }

    @Test
    fun `a changing address still has records to create once`() {
        assertTrue(WizardStep.DNS in wizardSteps(form(scope = DeploymentScope.DYNAMIC_DNS)))
    }

    @Test
    fun `the admin step appears only when something signs in with that login`() {
        val admin = ServiceRegistry.all.first { it.usesSharedAdminLogin }
        val plain = ServiceRegistry.all.first { !it.usesSharedAdminLogin }
        assertTrue(WizardStep.ADMIN in wizardSteps(form(services = setOf(admin.id))))
        assertFalse(WizardStep.ADMIN in wizardSteps(form(services = setOf(plain.id))))
    }

    @Test
    fun `the protocol step appears with the VPN shelf and not before`() {
        val protocol = ServiceRegistry.services(ServiceCategory.VPN).first()
        assertFalse(WizardStep.VPN_PROTOCOL in wizardSteps(form()))
        assertTrue(WizardStep.VPN_PROTOCOL in wizardSteps(form(services = setOf(protocol.id))))
    }

    /** NEGATIVE CONTROL for the pin */
    @Test
    fun `the protocol page stays while it is the page being answered`() {
        assertTrue(WizardStep.VPN_PROTOCOL in wizardSteps(form(), standingOnVpnStep = true))
    }

    @Test
    fun `review closes every path`() {
        for (scope in DeploymentScope.entries) {
            val steps = wizardSteps(form(scope = scope))
            assertEquals(WizardStep.REVIEW, steps.last(), "$scope -> $steps")
            assertEquals(steps.size, steps.distinct().size, "a step asked twice: $steps")
        }
    }

    @Test
    fun `the relay pair asks the same questions as one machine`() {
        assertEquals(
            wizardSteps(form(topology = Topology.SINGLE_HOST)),
            wizardSteps(form(topology = Topology.VPS_RELAY_WITH_HOME_BACKEND)),
        )
    }
}
