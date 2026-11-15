package com.skaymer.gryonixnexus.catalog

import com.skaymer.gryonixnexus.catalog.services.TailscaleNodeService
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class TailscaleOnlyScopeTest {
    @Test
    fun `tailscale-only brings the node but no control server`() {
        val ids = ServiceRegistry.expanded(setOf(ServiceID.VAULTWARDEN), DeploymentScope.TAILSCALE_ONLY, ModelBackend.HERE)
        assertTrue(ServiceID.TAILSCALE_NODE in ids)
        assertFalse(ServiceID.HEADSCALE in ids, "a Headscale behind a router cannot be reached from outside")
    }

    @Test
    fun `tailscale-only behaves like an outbound-only scope`() {
        val scope = DeploymentScope.TAILSCALE_ONLY
        assertTrue(scope.usesInternalTLS)
        assertFalse(scope.carriesNonWebServices)
        assertFalse(scope.publishesAddressRecords)
        assertFalse(scope.requiresMesh)
        assertEquals(listOf(scope), DeploymentScope.entries.filter { it.joinsTailscale })
        assertEquals("tailscaleOnly", scope.wireValue)
    }

    private fun script(withHeadscale: Boolean): String {
        val installed = if (withHeadscale) setOf(ServiceID.HEADSCALE, ServiceID.TAILSCALE_NODE)
        else setOf(ServiceID.TAILSCALE_NODE)
        val context = ServiceContext(domain = "example.com", sshUser = "server-user", installedServices = installed)
        return TailscaleNodeService().setupSteps(context).joinToString("\n")
    }

    @Test
    fun `without a control server of ours the node never talks to headscale`() {
        val text = script(withHeadscale = false)
        assertFalse("headscale" in text)
        assertTrue("TS_AUTHKEY" in text)
    }

    @Test
    fun `beside headscale the node still mints its own key`() {
        assertTrue("preauthkeys create" in script(withHeadscale = true))
    }
}
