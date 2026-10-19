package com.skaymer.gryonixnexus.app.configurator

import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceSettings
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.core.DistributionProfileID
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The configurator form built from a server that already exists */
class ReinstallFormTests {
    private fun server(
        services: Set<ServiceID> = setOf(ServiceID.NEXTCLOUD),
        scope: DeploymentScope = DeploymentScope.PUBLIC_INTERNET,
        serviceSettings: ServiceSettings = ServiceSettings(),
    ) = Deployment(
        id = "S-1",
        name = "middle",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        additionalDomains = listOf("second.test"),
        entry = HostEndpoint(host = "203.0.113.40", port = 2200, user = "control"),
        services = services,
        scope = scope,
        serviceSettings = serviceSettings,
    )

    @Test
    fun `the form describes the server it came from`() {
        val form = ConfiguratorForm.of(server())
        assertEquals(Topology.SINGLE_HOST, form.topology)
        assertEquals("example.test", form.domain)
        assertEquals(listOf("second.test"), form.additionalDomains)
        assertEquals("203.0.113.40", form.publicIP)
        assertEquals(setOf(ServiceID.NEXTCLOUD), form.services)
    }

    @Test
    fun `the scope comes back rather than being assumed public`() {
        val form = ConfiguratorForm.of(server(scope = DeploymentScope.LOCAL_ONLY))
        assertEquals(DeploymentScope.LOCAL_ONLY, form.scope)
        assertTrue(form.isLocalOnly)
    }

    @Test
    fun `the app keeps the access it already has`() {
        val form = ConfiguratorForm.of(server())
        assertTrue(form.includeDashboardAccess)
        assertEquals("control", form.dashboardSSHUser)
        assertTrue(form.useExistingUser)
    }

    @Test
    fun `a distribution nobody recorded is the default rather than nothing`() {
        assertEquals(DistributionProfileID.DEBIAN, ConfiguratorForm.of(server()).distribution)
    }

    @Test
    fun `the per-service answers this server was installed with come back`() {
        val recorded = ServiceSettings(
            minecraftJavaAcceptsEULA = true,
            vaultwardenAllowSignups = false,
            piholeServesNetwork = true,
        )
        val form = ConfiguratorForm.of(
            server(services = setOf(ServiceID.MINECRAFT_JAVA), serviceSettings = recorded),
        )
        assertEquals(recorded, form.serviceSettings)
        assertTrue(
            form.serviceSettings.minecraftJavaAcceptsEULA,
            "a license this server was installed under must not have to be accepted again",
        )
        assertTrue(
            !form.serviceSettings.vaultwardenAllowSignups,
            "open registration must not come back on for a server whose owner closed it",
        )
        assertTrue(
            ServiceQuestions.unanswered(form).isEmpty(),
            "the reinstall of a running game server must not stop at a question its own " +
                "record already answers",
        )
    }
}
