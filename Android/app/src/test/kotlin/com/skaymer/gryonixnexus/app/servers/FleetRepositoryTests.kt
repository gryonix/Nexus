package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.app.access.AccessCredential
import com.skaymer.gryonixnexus.app.access.AccessCredentialStore
import com.skaymer.gryonixnexus.app.access.InstallReportStore
import com.skaymer.gryonixnexus.app.secrets.DeploymentSecrets
import com.skaymer.gryonixnexus.app.secrets.InMemorySecretStore
import com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentStore
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.ServerCardSize
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import com.skaymer.gryonixnexus.app.licensing.LicenseGate
import com.skaymer.gryonixnexus.app.licensing.LicensePrompt
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

class FleetRepositoryTests {
    @BeforeEach
    fun licensed() {
        LicenseGate.unlocked = true
    }

    @AfterEach
    fun locked() {
        LicenseGate.unlocked = false
        LicensePrompt.showing.value = false
    }

    private class RecordingStore(initial: List<Deployment> = emptyList()) : DeploymentStore {
        var saved: List<Deployment>? = null
        private var contents = initial
        override fun load(): List<Deployment> = contents
        override fun save(deployments: List<Deployment>) {
            saved = deployments
            contents = deployments
        }
    }

    private fun server(id: String, size: ServerCardSize? = null) = Deployment(
        id = id,
        name = id,
        topology = Topology.SINGLE_HOST,
        domain = "$id.test",
        entry = HostEndpoint(host = "203.0.113.1", user = "root"),
        cardSize = size
    )

    @Test
    fun `the stored fleet is what is drawn when no demo count is set`() {
        val store = RecordingStore(listOf(server("alpha"), server("beta")))
        val fleet = FleetRepository(store, InMemorySettingsStore(), eraser())
        fleet.reload()

        assertEquals(listOf("alpha", "beta"), fleet.deployments.value.map { it.id })
        assertTrue(!fleet.isDemo)
    }

    @Test
    fun `a fresh install with no servers opens on the demo fleet`() {
        val settings = InMemorySettingsStore()
        val fleet = FleetRepository(RecordingStore(), settings, eraser())
        fleet.reload()

        assertTrue(fleet.isDemo)
        assertEquals(DemoDeployments.FULL_COUNT.toInt(), fleet.deployments.value.size)
    }

    @Test
    fun `adding the first real server leaves the first-launch demo`() {
        val fleet = FleetRepository(RecordingStore(), InMemorySettingsStore(), eraser())
        fleet.reload()
        fleet.add(server("alpha"))

        assertFalse(fleet.isDemo)
        assertEquals(listOf("alpha"), fleet.deployments.value.map { it.id })
    }

    @Test
    fun `a demo count replaces the fleet with the synthetic one`() {
        val store = RecordingStore(listOf(server("alpha")))
        val settings = InMemorySettingsStore()
        settings.setString(DemoDeployments.COUNT_KEY, "4")
        val fleet = FleetRepository(store, settings, eraser())
        fleet.reload()

        assertEquals(4, fleet.deployments.value.size)
        assertTrue(fleet.deployments.value.none { it.id == "alpha" }, "the real fleet leaked in")
        assertTrue(fleet.isDemo)
    }

    /** The one that matters */
    @Test
    fun `an edit during a demo run never reaches the store`() {
        val store = RecordingStore(listOf(server("alpha")))
        val settings = InMemorySettingsStore()
        settings.setString(DemoDeployments.COUNT_KEY, "2")
        val fleet = FleetRepository(store, settings, eraser())
        fleet.reload()

        val target = fleet.deployments.value.first()
        fleet.setCardSize(target.id, ServerCardSize.COMPACT)

        assertEquals(
            ServerCardSize.COMPACT,
            fleet.deployments.value.first { it.id == target.id }.cardSize,
            "the edit did not reach the screen either"
        )
        assertNull(store.saved, "a demo run wrote to the owner's real fleet")
        assertEquals(listOf("alpha"), store.load().map { it.id })
    }

    @Test
    fun `an edit on the real fleet is persisted`() {
        val store = RecordingStore(listOf(server("alpha")))
        val fleet = FleetRepository(store, InMemorySettingsStore(), eraser())
        fleet.reload()

        fleet.setCardSize("alpha", ServerCardSize.COMPACT)

        assertEquals(
            ServerCardSize.COMPACT,
            store.saved?.single()?.cardSize,
            "the card size never reached the file"
        )
    }

    @Test
    fun `clearing the size puts the server back on the app default`() {
        val store = RecordingStore(listOf(server("alpha", ServerCardSize.COMPACT)))
        val fleet = FleetRepository(store, InMemorySettingsStore(), eraser())
        fleet.reload()

        fleet.setCardSize("alpha", null)

        assertNull(fleet.deployments.value.single().cardSize)
        assertNull(store.saved?.single()?.cardSize)
    }

    @Test
    fun `adding a machine leaves the demo fleet and shows the real one`() {
        val store = RecordingStore()
        val settings = InMemorySettingsStore()
        settings.setString(DemoDeployments.COUNT_KEY, "4")
        val fleet = FleetRepository(store, settings, eraser())
        fleet.reload()
        assertTrue(fleet.isDemo)

        fleet.add(server("added"))

        assertFalse(fleet.isDemo)
        assertEquals(listOf("added"), fleet.deployments.value.map { it.id })
        assertEquals(listOf("added"), store.load().map { it.id })
    }

    @Test
    fun `an edit to an unknown server changes nothing`() {
        val store = RecordingStore(listOf(server("alpha")))
        val fleet = FleetRepository(store, InMemorySettingsStore(), eraser())
        fleet.reload()

        fleet.setCardSize("nobody", ServerCardSize.COMPACT)

        assertEquals(listOf("alpha"), fleet.deployments.value.map { it.id })
        assertNull(store.saved)
    }

    // ------------------------------------------------- The domain the server states

    @Test
    fun `an empty domain is filled from the report`() {
        val blank = server("alpha").copy(domain = "")
        val store = RecordingStore(listOf(blank))
        val fleet = FleetRepository(store, InMemorySettingsStore(), eraser())
        fleet.reload()

        fleet.adoptDomain(blank, "Example.COM")
        assertEquals("example.com", fleet.deployments.value.single().domain)
        assertEquals("example.com", store.saved?.single()?.domain)
    }

    /** Only ever FILLS an empty one */
    @Test
    fun `a domain that is already set is left alone`() {
        val named = server("alpha")
        val store = RecordingStore(listOf(named))
        val fleet = FleetRepository(store, InMemorySettingsStore(), eraser())
        fleet.reload()

        fleet.adoptDomain(named, "somewhere.else")
        assertEquals("alpha.test", fleet.deployments.value.single().domain)
        assertNull(store.saved, "nothing was worth writing")
    }

    @Test
    fun `adopting a domain while the demo fleet is on screen writes nothing`() {
        val store = RecordingStore()
        val settings = InMemorySettingsStore()
        settings.setString(DemoDeployments.COUNT_KEY, "2")
        val fleet = FleetRepository(store, settings, eraser())
        fleet.reload()

        fleet.adoptDomain(fleet.deployments.value.first().copy(domain = ""), "example.com")
        assertNull(store.saved)
    }

    // ------------------------------------------------- Taking a server off the list

    @Test
    fun `removing a server takes its entry and its secrets with it`() {
        val store = RecordingStore(listOf(server("alpha"), server("beta")))
        val secrets = InMemorySecretStore()
        DeploymentSecrets(secrets, "alpha").setIdentitySeed(ByteArray(32))
        AccessCredentialStore(secrets, "alpha")
            .save(mapOf("host|Nextcloud" to AccessCredential(login = "admin")))
        InstallReportStore(secrets, "alpha").save(host = "single", text = "report")
        val fleet = FleetRepository(store, InMemorySettingsStore(), DeploymentEraser(secrets))
        fleet.reload()

        fleet.remove("alpha")

        assertEquals(listOf("beta"), fleet.deployments.value.map { it.id }, "still on screen")
        assertEquals(listOf("beta"), store.load().map { it.id }, "still in the file")
        assertTrue(secrets.items.isEmpty(), "left behind: ${secrets.items.keys}")
    }

    @Test
    fun `removing a server leaves the other servers signed in`() {
        val store = RecordingStore(listOf(server("alpha"), server("beta")))
        val secrets = InMemorySecretStore()
        DeploymentSecrets(secrets, "beta").setIdentitySeed(ByteArray(32) { 7 })
        val fleet = FleetRepository(store, InMemorySettingsStore(), DeploymentEraser(secrets))
        fleet.reload()

        fleet.remove("alpha")

        assertContentEquals(
            ByteArray(32) { 7 },
            DeploymentSecrets(secrets, "beta").identitySeed(),
            "another server's key was erased"
        )
    }

    @Test
    fun `removing a demo server changes neither store`() {
        val store = RecordingStore(listOf(server("alpha")))
        val settings = InMemorySettingsStore()
        settings.setString(DemoDeployments.COUNT_KEY, "2")
        val secrets = InMemorySecretStore()
        DeploymentSecrets(secrets, "alpha").setIdentitySeed(ByteArray(32))
        val fleet = FleetRepository(store, settings, DeploymentEraser(secrets))
        fleet.reload()
        val target = fleet.deployments.value.first()

        fleet.remove(target.id)

        assertEquals(1, fleet.deployments.value.size, "the card stayed on screen")
        assertNull(store.saved, "a demo run wrote to the owner's real fleet")
        assertEquals(listOf("alpha"), store.load().map { it.id })
        assertTrue(secrets.items.isNotEmpty(), "a demo run erased a real server's key")
    }

    @Test
    fun `removing an unknown server changes nothing`() {
        val store = RecordingStore(listOf(server("alpha")))
        val secrets = InMemorySecretStore()
        DeploymentSecrets(secrets, "alpha").setIdentitySeed(ByteArray(32))
        val fleet = FleetRepository(store, InMemorySettingsStore(), DeploymentEraser(secrets))
        fleet.reload()

        fleet.remove("nobody")

        assertEquals(listOf("alpha"), fleet.deployments.value.map { it.id })
        assertNull(store.saved)
        assertTrue(secrets.items.isNotEmpty())
    }

    @Test
    fun `a locked copy shows the demo fleet over real servers`() {
        LicenseGate.unlocked = false
        val fleet = FleetRepository(RecordingStore(listOf(server("alpha"))), InMemorySettingsStore(), eraser())
        fleet.reload()

        assertTrue(fleet.isDemo)
    }
}
