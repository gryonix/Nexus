package com.skaymer.gryonixnexus.app.configurator

import com.skaymer.gryonixnexus.app.secrets.InMemorySecretStore
import com.skaymer.gryonixnexus.app.servers.FleetRepository
import com.skaymer.gryonixnexus.app.servers.InMemoryDeploymentStore
import com.skaymer.gryonixnexus.app.servers.eraser
import com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceSettings
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.ServerCardSize
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** What a reinstall writes into the fleet */
class DeploymentRecorderTests {
    private fun fleet() = FleetRepository(InMemoryDeploymentStore(), InMemorySettingsStore(), eraser())

    private fun form() = ConfiguratorForm(
        topology = Topology.SINGLE_HOST,
        domain = "example.com",
        publicIP = "203.0.113.10",
        dashboardSSHUser = "server-user",
        serviceSettings = ServiceSettings(mailcowPath = "/srv/mailcow"),
    )

    private fun installed(id: String) = Deployment(
        id = id,
        name = "middle",
        topology = Topology.SINGLE_HOST,
        domain = "example.com",
        entry = HostEndpoint(host = "203.0.113.10", user = "server-user"),
        services = setOf(ServiceID.VAULTWARDEN),
        usesAgent = true,
        tags = listOf("prod"),
        cardSize = ServerCardSize.COMPACT,
    )

    @Test
    fun `repairing a server keeps the agent the app found on it`() {
        val fleet = fleet()
        val existing = installed("S-1")
        fleet.add(existing)
        val recorder = DeploymentRecorder(fleet, InMemorySecretStore())

        val id = recorder.identify(form(), carried = null)
        assertEquals(existing.id, id, "a form describing a server in the fleet continues it")

        val record = recorder.record(id, form(), setOf(ServiceID.VAULTWARDEN), emptyMap())
        assertTrue(
            record.usesAgent,
            "a repair made the app forget the daemon it manages this server through",
        )
        assertTrue(fleet.deployments.value.single().usesAgent, "and forgot it on disk too")
        assertEquals(listOf("prod"), record.tags)
        assertEquals(ServerCardSize.COMPACT, record.cardSize)
    }

    @Test
    fun `the recorded server carries the settings it was generated from`() {
        val fleet = fleet()
        val recorder = DeploymentRecorder(fleet, InMemorySecretStore())
        val record = recorder.record(
            recorder.identify(form(), carried = null),
            form(),
            setOf(ServiceID.MAILCOW),
            emptyMap(),
        )
        assertEquals("/srv/mailcow", record.serviceSettings.mailcowPath)
    }

    @Test
    fun `a server nobody has installed yet is recorded as generated`() {
        val fleet = fleet()
        val recorder = DeploymentRecorder(fleet, InMemorySecretStore())
        val record = recorder.record(
            recorder.identify(form(), carried = null),
            form(),
            setOf(ServiceID.VAULTWARDEN),
            emptyMap(),
        )
        assertEquals(false, record.usesAgent)
        assertEquals(emptyList(), record.tags)
    }
}
