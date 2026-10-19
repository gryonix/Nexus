package com.skaymer.gryonixnexus.app.configurator

import com.skaymer.gryonixnexus.app.licensing.LicenseGate
import com.skaymer.gryonixnexus.app.secrets.InMemorySecretStore
import com.skaymer.gryonixnexus.app.servers.DemoDeployments
import com.skaymer.gryonixnexus.app.servers.FleetRepository
import com.skaymer.gryonixnexus.app.servers.InMemoryDeploymentStore
import com.skaymer.gryonixnexus.app.servers.eraser
import com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Test

class DashboardAccessTests {
    @AfterEach
    fun lockAgain() {
        LicenseGate.unlocked = false
    }

    private class World(licensed: Boolean = true) {
        init {
            LicenseGate.unlocked = licensed
        }

        val store = InMemoryDeploymentStore()
        val secrets = InMemorySecretStore()
        private val settings = InMemorySettingsStore().apply {
            setString(DemoDeployments.COUNT_KEY, "0")
        }
        val fleet = FleetRepository(store, settings, eraser()).also { it.reload() }
        val model = ConfiguratorViewModel(fleet = fleet, secrets = secrets)

        fun fill() = model.update {
            it.copy(domain = "example.com", publicIP = "203.0.113.10")
        }

        fun withAccess() = model.update { it.copy(includeDashboardAccess = true) }
    }

    @Test
    fun `the script carries this devices own public key`() {
        val world = World()
        world.fill()
        world.withAccess()
        world.model.toggle(ServiceID.NEXTCLOUD)
        world.model.generate()

        val key = assertNotNull(world.model.appPublicKey())
        val bundle = assertNotNull(world.model.bundle.value, world.model.error.value)
        val scripts = bundle.artifacts.filter { it.fileName.endsWith(".sh") }
        assertTrue(scripts.isNotEmpty(), "no script generated")
        assertTrue(
            scripts.any { key in it.contents },
            "the app's key is in no script — the server would never authorise it"
        )
    }

    /** And without the toggle it is in none of them */
    @Test
    fun `without the toggle no script carries a key`() {
        val world = World()
        world.fill()
        world.model.toggle(ServiceID.NEXTCLOUD)
        world.model.generate()

        val bundle = assertNotNull(world.model.bundle.value, world.model.error.value)
        assertTrue(
            bundle.artifacts.none { "ssh-ed25519 " in it.contents },
            "a bundle that grants nothing still carried a key"
        )
        assertNull(world.model.savedDeployment.value, "and it recorded no server")
        assertTrue(world.fleet.deployments.value.isEmpty())
    }

    @Test
    fun `without a license the generated server is not kept`() {
        val world = World(licensed = false)
        world.fill()
        world.withAccess()
        world.model.toggle(ServiceID.NEXTCLOUD)
        world.model.generate()

        assertNotNull(world.model.savedDeployment.value, "the install still needs a server to run on")
        assertTrue(world.fleet.deployments.value.isEmpty(), "but the fleet keeps none")
    }

    @Test
    fun `without a license the form keeps no address of its own`() {
        val world = World(licensed = false)
        world.model.update {
            it.copy(
                domain = "mine.example.org",
                publicIP = "198.51.100.7",
                additionalDomains = listOf("second.example.org"),
                reverseDNSHostname = "mail.example.org",
            )
        }

        world.model.useDemoAddressesIfLocked()

        val form = world.model.form.value
        assertEquals(ConfiguratorViewModel.DEMO_DOMAIN, form.domain)
        assertEquals(ConfiguratorViewModel.DEMO_PUBLIC_IP, form.publicIP)
        assertTrue(form.additionalDomains.isEmpty())
        assertTrue(form.reverseDNSHostname.isEmpty())
    }

    @Test
    fun `with a license the form keeps what the user typed`() {
        val world = World(licensed = true)
        world.model.update { it.copy(domain = "mine.example.org", publicIP = "198.51.100.7") }

        world.model.useDemoAddressesIfLocked()

        assertEquals("mine.example.org", world.model.form.value.domain)
    }

    @Test
    fun `generating with access records the server the scripts describe`() {
        val world = World()
        world.fill()
        world.withAccess()
        world.model.update { it.copy(dashboardSSHUser = "Server-User") }
        world.model.toggle(ServiceID.WIREGUARD_VPN)
        world.model.generate()

        val saved = assertNotNull(world.model.savedDeployment.value, world.model.error.value)
        assertEquals("example.com", saved.domain)
        assertEquals("203.0.113.10", saved.entry.host)
        assertEquals("server-user", saved.entry.user, "the account name has to match sudoers")
        assertTrue(ServiceID.VPN_PANEL in saved.services, "the implied service was not recorded")
        assertEquals(listOf(saved), world.fleet.deployments.value)
    }

    /** Regenerating the same configuration is the same server */
    @Test
    fun `regenerating one configuration keeps one server`() {
        val world = World()
        world.fill()
        world.withAccess()
        world.model.generate()
        val first = assertNotNull(world.model.savedDeployment.value)

        world.model.toggle(ServiceID.NEXTCLOUD)
        world.model.generate()
        val second = assertNotNull(world.model.savedDeployment.value)

        assertEquals(first.id, second.id)
        assertEquals(1, world.fleet.deployments.value.size)
    }

    @Test
    fun `changing the domain after a save gives the new server its own identity`() {
        val world = World()
        world.fill()
        world.withAccess()
        world.model.generate()
        val first = assertNotNull(world.model.savedDeployment.value)

        world.model.update { it.copy(domain = "other.example") }
        world.model.generate()
        val second = assertNotNull(world.model.savedDeployment.value, world.model.error.value)

        assertNotEquals(first.id, second.id)
        assertEquals(2, world.fleet.deployments.value.size)
        assertTrue(world.fleet.deployments.value.any { it.id == first.id && it.domain == "example.com" })
    }

    @Test
    fun `a domain already in the fleet continues that servers identity`() {
        val world = World()
        val existing = Deployment(
            id = "EXISTING-ID",
            name = "example.com",
            topology = Topology.SINGLE_HOST,
            domain = "example.com",
            entry = HostEndpoint(host = "203.0.113.10", user = "server-user"),
        )
        world.store.save(listOf(existing))
        world.fleet.reload()

        world.fill()
        world.withAccess()
        world.model.generate()

        assertEquals("EXISTING-ID", world.model.savedDeployment.value?.id)
        assertEquals(1, world.fleet.deployments.value.size)
    }

    @Test
    fun `an existing account without a password refuses to generate`() {
        val world = World()
        world.fill()
        world.withAccess()
        world.model.update { it.copy(useExistingUser = true) }
        world.model.generate()

        assertNull(world.model.bundle.value)
        assertNull(world.model.savedDeployment.value)
        assertNotNull(world.model.error.value)
        assertTrue(world.fleet.deployments.value.isEmpty(), "and no server was written")
    }

    @Test
    fun `the existing accounts password is stored and stays out of the artefacts`() {
        val world = World()
        world.fill()
        world.withAccess()
        world.model.update { it.copy(useExistingUser = true) }
        world.model.setPassword(SSHHostID.VPS, "s3cret-passphrase")
        world.model.generate()

        val saved = assertNotNull(world.model.savedDeployment.value, world.model.error.value)
        assertTrue(saved.usesPasswordAuth, "the dashboard has to know to sign in with a password")
        val bundle = assertNotNull(world.model.bundle.value)
        assertTrue(
            bundle.artifacts.none { "s3cret-passphrase" in it.contents },
            "the password was printed into an artefact"
        )
        assertTrue(
            world.secrets.items.values.any { it.toString(Charsets.UTF_8) == "s3cret-passphrase" },
            "the password never reached the keystore, so the dashboard cannot sign in"
        )
    }

    @Test
    fun `scenario B asks for the second machines password too`() {
        val world = World()
        world.fill()
        world.withAccess()
        world.model.update {
            it.copy(topology = Topology.VPS_RELAY_WITH_HOME_BACKEND, useExistingUser = true)
        }
        world.model.setPassword(SSHHostID.VPS, "relay-password")
        world.model.generate()

        assertNull(world.model.bundle.value, "one password was accepted for two machines")

        world.model.setPassword(SSHHostID.HOME, "home-password")
        world.model.generate()
        assertNotNull(world.model.bundle.value, world.model.error.value)
    }

    /** The identity is generated once and then only derived */
    @Test
    fun `the same deployment keeps the same key`() {
        val world = World()
        world.fill()
        world.withAccess()
        val first = assertNotNull(world.model.appPublicKey())
        val second = assertNotNull(world.model.appPublicKey())
        assertEquals(first, second)
        assertTrue(first.startsWith("ssh-ed25519 "))
    }
}
