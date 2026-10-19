package com.skaymer.gryonixnexus.app.configurator

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.app.secrets.InMemorySecretStore
import com.skaymer.gryonixnexus.app.servers.FleetRepository
import com.skaymer.gryonixnexus.app.servers.InMemoryDeploymentStore
import com.skaymer.gryonixnexus.app.servers.eraser
import com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** When the Zigbee stick may be picked instead of typed */
class SerialDevicePickerTests {
    private fun server(usesAgent: Boolean) = Deployment(
        id = "11111111-1111-1111-1111-111111111111",
        name = "home",
        topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        domain = "example.net",
        entry = HostEndpoint(host = "203.0.113.10", user = "root"),
        services = setOf(ServiceID.HOME_ASSISTANT),
        usesAgent = usesAgent,
    )

    private fun model(client: (suspend (Deployment) -> AgentClient?)? = { null }) =
        ConfiguratorViewModel(
            fleet = FleetRepository(InMemoryDeploymentStore(), InMemorySettingsStore(), eraser()),
            secrets = InMemorySecretStore(),
            scope = CoroutineScope(Dispatchers.Unconfined),
            agentClient = client,
        )

    /** A fresh install has no machine to ask yet */
    @Test
    fun `the configurator with no server behind it offers no picker`() {
        assertFalse(model().canListSerialDevices)
    }

    /** The listing is an agent verb; SSH-only cannot answer */
    @Test
    fun `a server without an agent offers no picker`() {
        val vm = model()
        vm.adopt(ConfiguratorForm(), server(usesAgent = false))
        assertFalse(vm.canListSerialDevices)
    }

    @Test
    fun `a server with an agent offers the picker`() {
        val vm = model()
        vm.adopt(ConfiguratorForm(), server(usesAgent = true))
        assertTrue(vm.canListSerialDevices)
        assertEquals(ConfiguratorViewModel.SerialListing.Idle, vm.serialListing.value)
    }

    /** No agent behind the call is said, not shown */
    @Test
    fun `a server the session cannot reach reports it instead of an empty list`() {
        val vm = model(client = { null })
        vm.adopt(ConfiguratorForm(), server(usesAgent = true))
        vm.loadSerialDevices()
        assertEquals(
            ConfiguratorViewModel.SerialListing.Failed(ConfiguratorViewModel.NO_AGENT),
            vm.serialListing.value,
        )
    }

    /** Adopting another server empties the list */
    @Test
    fun `adopting another server resets the listing`() {
        val vm = model(client = { null })
        vm.adopt(ConfiguratorForm(), server(usesAgent = true))
        vm.loadSerialDevices()
        vm.adopt(ConfiguratorForm(), server(usesAgent = true))
        assertEquals(ConfiguratorViewModel.SerialListing.Idle, vm.serialListing.value)
    }

    /** An empty list means two different things */
    @Test
    fun `an empty listing keeps the difference between no stick and no usb at all`() {
        assertTrue(
            ConfiguratorViewModel.SerialListing.Loaded(emptyList(), directoryPresent = true) !=
                ConfiguratorViewModel.SerialListing.Loaded(emptyList(), directoryPresent = false),
        )
    }
}
