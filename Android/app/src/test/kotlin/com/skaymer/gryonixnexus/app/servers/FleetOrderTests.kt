package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import kotlin.test.assertEquals
import com.skaymer.gryonixnexus.app.licensing.LicenseGate
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

class FleetOrderTests {
    @BeforeEach
    fun licensed() {
        LicenseGate.unlocked = true
    }

    @AfterEach
    fun locked() {
        LicenseGate.unlocked = false
    }

    private fun server(id: String) = Deployment(
        id = id,
        name = id,
        topology = Topology.SINGLE_HOST,
        entry = HostEndpoint(host = "203.0.113.1", user = "root"),
    )

    private fun names(list: List<Deployment>) = list.map { it.id }

    @Test
    fun `a server moves, and the ones it passes keep their order`() {
        val list = listOf(server("a"), server("b"), server("c"), server("d"))
        assertEquals(listOf("c", "a", "b", "d"), names(FleetOrder.moved(list, from = 2, to = 0)))
        assertEquals(listOf("a", "c", "d", "b"), names(FleetOrder.moved(list, from = 1, to = 3)))
    }

    @Test
    fun `a move that cannot happen changes nothing`() {
        val list = listOf(server("a"), server("b"))
        for (pair in listOf(-1 to 0, 0 to 5, 2 to 1, 1 to 1)) {
            assertEquals(names(list), names(FleetOrder.moved(list, pair.first, pair.second)))
        }
    }

    @Test
    fun `the file is what remembers the order`() {
        val store = InMemoryDeploymentStore(listOf(server("a"), server("b"), server("c")))
        val fleet = FleetRepository(store, InMemorySettingsStore(), eraser = DeploymentEraser(
            com.skaymer.gryonixnexus.app.secrets.InMemorySecretStore(),
        ))
        fleet.reload()

        fleet.move(from = 2, to = 0)

        assertEquals(listOf("c", "a", "b"), names(store.load()))
        assertEquals(listOf("c", "a", "b"), names(fleet.deployments.value))
    }

    @Test
    fun `the ends of the list know they are the ends`() {
        assertEquals(false, FleetOrder.canMoveUp(0))
        assertEquals(true, FleetOrder.canMoveUp(1))
        assertEquals(false, FleetOrder.canMoveDown(2, count = 3))
        assertEquals(true, FleetOrder.canMoveDown(1, count = 3))
    }
}
