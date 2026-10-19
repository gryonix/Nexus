package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.NodeCapability
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** Editing the address of a machine already in the fleet */
class ConnectionEditTests {
    private fun single() = Deployment(
        id = "alpha",
        name = "alpha",
        topology = Topology.SINGLE_HOST,
        entry = HostEndpoint(host = "203.0.113.1", port = 22, user = "root"),
    )

    private fun withStoredNodes() = single().copy(
        storedNodes = listOf(
            DeploymentNode(
                id = "n1",
                endpoint = HostEndpoint(host = "203.0.113.1", user = "root"),
                capabilities = setOf(NodeCapability.INGRESS, NodeCapability.WORKER),
                legacySlot = DeploymentNode.LegacySlot.VPS,
            ),
            DeploymentNode(
                id = "n2",
                endpoint = HostEndpoint(host = "10.8.0.2", user = "ops"),
                capabilities = setOf(NodeCapability.WORKER),
            ),
        ),
    )

    @Test
    fun `an edited machine keeps its address and leaves its neighbour alone`() {
        val deployment = withStoredNodes()
        val second = deployment.nodes[1]
        val updated = ConnectionEdit.applying(
            ConnectionEdit.Draft(host = "10.8.0.9", port = "2222", user = "admin"),
            to = second,
            of = deployment,
        )!!
        assertEquals("10.8.0.9", updated.nodes[1].endpoint.host)
        assertEquals(2222, updated.nodes[1].endpoint.port)
        assertEquals("admin", updated.nodes[1].endpoint.user)
        assertEquals("203.0.113.1", updated.nodes[0].endpoint.host)
        assertEquals(22, updated.nodes[0].endpoint.port)
    }

    @Test
    fun `a single host is edited through its entry, not by freezing a node list`() {
        val deployment = single()
        val updated = ConnectionEdit.applying(
            ConnectionEdit.Draft(host = " 198.51.100.7 ", port = "22", user = " root "),
            to = deployment.nodes.single(),
            of = deployment,
        )!!
        assertEquals("198.51.100.7", updated.entry.host)
        assertEquals("root", updated.entry.user)
        assertNull(updated.storedNodes)
    }

    @Test
    fun `nothing incomplete or impossible is ever written`() {
        val deployment = single()
        val node = deployment.nodes.single()
        for (draft in listOf(
            ConnectionEdit.Draft(host = "  ", port = "22", user = "root"),
            ConnectionEdit.Draft(host = "h", port = "22", user = " "),
            ConnectionEdit.Draft(host = "h", port = "0", user = "root"),
            ConnectionEdit.Draft(host = "h", port = "65536", user = "root"),
            ConnectionEdit.Draft(host = "h", port = "", user = "root"),
        )) {
            assertTrue(!draft.isComplete, "$draft should be incomplete")
            assertNull(ConnectionEdit.applying(draft, node, deployment))
        }
    }

    @Test
    fun `a machine from another server cannot be edited into this one`() {
        val target = withStoredNodes()
        val stranger = DeploymentNode(
            id = "z9",
            endpoint = HostEndpoint(host = "198.51.100.9", user = "root"),
            capabilities = setOf(NodeCapability.WORKER),
            legacySlot = DeploymentNode.LegacySlot.VPS,
        )
        assertNull(
            ConnectionEdit.applying(
                ConnectionEdit.Draft(host = "h", port = "22", user = "root"),
                to = stranger,
                of = target,
            ),
        )
    }

    @Test
    fun `only machines with an address of their own are offered`() {
        val pair = single().copy(
            topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
            homeWGAddress = "10.8.0.2",
        )
        assertEquals(2, pair.nodes.size)
        assertEquals(
            listOf(DeploymentNode.LegacySlot.VPS),
            ConnectionEdit.editable(pair).map { it.legacySlot },
        )
        assertEquals(2, ConnectionEdit.editable(withStoredNodes()).size)
    }
}
