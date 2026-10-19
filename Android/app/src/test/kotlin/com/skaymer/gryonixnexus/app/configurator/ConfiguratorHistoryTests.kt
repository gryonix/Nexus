package com.skaymer.gryonixnexus.app.configurator

import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceSettings
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.core.DistributionProfileID
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.nio.file.Path
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** What the configurator remembers, and what it must not lose */
class ConfiguratorHistoryTests {
    @TempDir
    lateinit var dir: Path

    private fun history(clock: () -> Long = { 1L }, ids: () -> String = { "id" }) =
        ConfiguratorHistory(File(dir.toFile(), "history.json"), clock, ids)

    private fun form() = ConfiguratorForm(
        topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        domain = "example.test",
        additionalDomains = listOf("second.test"),
        reverseDNSHostname = "relay.example.test",
        scope = DeploymentScope.PUBLIC_INTERNET,
        publicIP = "203.0.113.10",
        vpsVPNIP = "10.8.0.1",
        homeVPNIP = "10.8.0.2",
        distribution = DistributionProfileID.UBUNTU,
        homeDistribution = DistributionProfileID.DEBIAN,
        services = setOf(ServiceID.MAILCOW, ServiceID.NEXTCLOUD),
        includeDashboardAccess = true,
        dashboardSSHUser = "gryonix",
        useExistingUser = true,
        serviceSettings = ServiceSettings(vaultwardenAllowSignups = true, mailcowPath = "/srv/mail"),
    )

    /** Every answer comes back, not most of them */
    @Test
    fun `a restored entry is the configuration it was taken from`() {
        val store = history()
        store.append(form())
        assertEquals(form(), store.entries().single().toForm())
    }

    @Test
    fun `entries come back newest first`() {
        var now = 0L
        var next = 0
        val store = history(clock = { ++now }, ids = { "id-${next++}" })
        store.append(form().copy(domain = "first.test"))
        store.append(form().copy(domain = "second.test"))
        assertEquals(listOf("second.test", "first.test"), store.entries().map { it.domain })
    }

    /** Twenty, the same as the iPhone keeps */
    @Test
    fun `the history is capped and drops the oldest`() {
        var now = 0L
        var next = 0
        val store = history(clock = { ++now }, ids = { "id-${next++}" })
        repeat(25) { store.append(form().copy(domain = "host$it.test")) }
        val domains = store.entries().map { it.domain }
        assertEquals(20, domains.size)
        assertEquals("host24.test", domains.first())
        assertTrue("host4.test" !in domains, "the oldest five must be gone")
        assertEquals("host5.test", domains.last())
    }

    /** Each append is its own event */
    @Test
    fun `two runs of the same answers are two entries`() {
        var next = 0
        val store = history(ids = { "id-${next++}" })
        store.append(form())
        store.append(form())
        assertEquals(2, store.entries().size)
        assertEquals(2, store.entries().map { it.id }.toSet().size)
    }

    @Test
    fun `deleting removes only what was named`() {
        var next = 0
        val store = history(ids = { "id-${next++}" })
        store.append(form().copy(domain = "keep.test"))
        store.append(form().copy(domain = "drop.test"))
        val doomed = store.entries().first { it.domain == "drop.test" }.id
        store.delete(setOf(doomed))
        assertEquals(listOf("keep.test"), store.entries().map { it.domain })
    }

    /** A file this build cannot read is treated as absent */
    @Test
    fun `a corrupt file reads as no history`() {
        val file = File(dir.toFile(), "history.json")
        file.writeText("{ not json at all")
        assertEquals(emptyList(), ConfiguratorHistory(file).entries())
    }

    /** An entry written by a NEWER build still opens */
    @Test
    fun `an entry carrying an unknown field still restores`() {
        val file = File(dir.toFile(), "history.json")
        file.writeText(
            """[{"id":"a","savedAt":1,"domain":"example.test","somethingNewer":"x"}]"""
        )
        assertEquals("example.test", ConfiguratorHistory(file).entries().single().domain)
    }

    /** A service this build does not know is KEPT */
    @Test
    fun `an unknown service id survives the round trip`() {
        val file = File(dir.toFile(), "history.json")
        file.writeText("""[{"id":"a","savedAt":1,"services":["something-from-a-newer-build"]}]""")
        assertEquals(
            setOf(ServiceID("something-from-a-newer-build")),
            ConfiguratorHistory(file).entries().single().toForm().services,
        )
    }
}
