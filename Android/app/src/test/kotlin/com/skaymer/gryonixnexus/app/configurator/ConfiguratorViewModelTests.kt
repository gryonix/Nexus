package com.skaymer.gryonixnexus.app.configurator

import com.skaymer.gryonixnexus.app.licensing.LicenseGate
import com.skaymer.gryonixnexus.app.secrets.InMemorySecretStore
import com.skaymer.gryonixnexus.app.servers.FleetRepository
import com.skaymer.gryonixnexus.app.servers.InMemoryDeploymentStore
import com.skaymer.gryonixnexus.app.servers.eraser
import com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Test

class ConfiguratorViewModelTests {
    @AfterEach
    fun lockAgain() {
        LicenseGate.unlocked = false
    }

    private fun filled() = ConfiguratorViewModel(
        fleet = FleetRepository(InMemoryDeploymentStore(), InMemorySettingsStore(), eraser()),
        secrets = InMemorySecretStore(),
    ).apply {
        LicenseGate.unlocked = true
        update { it.copy(domain = "example.com", publicIP = "203.0.113.10") }
    }

    /** An exclusive shelf REPLACES rather than adds */
    @Test
    fun `picking a second engine on an exclusive shelf replaces the first`() {
        val model = filled()
        model.toggle(ServiceID.MAILCOW)
        model.toggle(ServiceID.DOCKER_MAILSERVER)

        assertEquals(setOf(ServiceID.DOCKER_MAILSERVER), model.form.value.services)
    }

    /** And a shelf that allows several keeps them all */
    @Test
    fun `a shelf that allows several keeps both`() {
        val model = filled()
        model.toggle(ServiceID.WIREGUARD_VPN)
        model.toggle(ServiceID.OPEN_VPN)

        assertTrue(ServiceID.WIREGUARD_VPN in model.form.value.services)
        assertTrue(ServiceID.OPEN_VPN in model.form.value.services)
    }

    /** Tapping the same service twice unpicks it */
    @Test
    fun `toggling a picked service removes it`() {
        val model = filled()
        model.toggle(ServiceID.NEXTCLOUD)
        model.toggle(ServiceID.NEXTCLOUD)
        assertTrue(model.form.value.services.isEmpty())
    }

    @Test
    fun `the vpn panel arrives with any protocol without being picked`() {
        val model = filled()
        model.toggle(ServiceID.WIREGUARD_VPN)

        assertFalse(ServiceID.VPN_PANEL in model.form.value.services, "nobody picked the panel")
        assertTrue(ServiceID.VPN_PANEL in model.installedServices(), "yet it is installed")
    }

    @Test
    fun `generating a single host produces its script and its dns records`() {
        val model = filled()
        model.toggle(ServiceID.NEXTCLOUD)
        model.generate()

        val bundle = model.bundle.value
        assertNotNull(bundle, "generation failed: ${model.error.value}")
        assertTrue(bundle.artifacts.isNotEmpty())
        assertTrue(
            bundle.artifacts.any { it.fileName.endsWith(".sh") },
            "no setup script in ${bundle.artifacts.map { it.fileName }}"
        )
        assertNull(model.error.value)
    }

    @Test
    fun `an invalid form reports the validators own words and drops the bundle`() {
        val model = filled()
        model.generate()
        assertNotNull(model.bundle.value)

        model.update { it.copy(domain = "not a domain") }
        model.generate()

        assertNull(model.bundle.value)
        assertNotNull(model.error.value)
        assertTrue(model.error.value!!.isNotBlank())
    }

    /** Editing the form throws away the last bundle */
    @Test
    fun `changing the form clears what was generated`() {
        val model = filled()
        model.generate()
        assertNotNull(model.bundle.value)

        model.update { it.copy(topology = Topology.VPS_RELAY_WITH_HOME_BACKEND) }

        assertNull(model.bundle.value, "the scripts of the previous answers stayed on screen")
    }
}
