package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.Topology
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class DemoDeploymentsTests {
    @Test
    fun `the handwritten fleet is four machines of different shapes`() {
        val fleet = DemoDeployments.fleet(DemoDeployments.SLOTS)
        assertEquals(4, fleet.size)
        assertTrue(fleet.any { it.topology == Topology.VPS_RELAY_WITH_HOME_BACKEND })
        assertTrue(fleet.any { it.topology == Topology.SINGLE_HOST })
        assertTrue(
            fleet.map { it.nodes.size }.toSet().size > 1,
            "every demo server has the same number of machines — the mixed fleet went flat"
        )
    }

    @Test
    fun `the same count gives the same fleet`() {
        assertEquals(
            DemoDeployments.fleet(6).map { it.id },
            DemoDeployments.fleet(6).map { it.id }
        )
    }

    @Test
    fun `a long fleet repeats without repeating an id`() {
        val fleet = DemoDeployments.fleet(10)
        assertEquals(10, fleet.size)
        assertEquals(10, fleet.map { it.id }.toSet().size, "an id was reused")
        assertEquals(10, fleet.map { it.name }.toSet().size, "a name was reused")
        assertEquals(
            fleet[0].name + " #2", fleet[DemoDeployments.SLOTS].name,
            "the second copy is not marked, so two identical names sit in one list"
        )
    }

    @Test
    fun `a count below one still gives one card`() {
        assertEquals(1, DemoDeployments.fleet(0).size)
    }
}
