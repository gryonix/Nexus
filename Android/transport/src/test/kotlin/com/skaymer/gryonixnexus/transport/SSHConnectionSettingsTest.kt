package com.skaymer.gryonixnexus.transport

import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.NodeCapability
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The join that makes a third machine real */
class SSHConnectionSettingsTest {
    private fun node(
        id: String,
        host: String,
        parent: String? = null,
        slot: DeploymentNode.LegacySlot? = null,
    ) = DeploymentNode(
        id = id,
        endpoint = HostEndpoint(host = host, port = 22, user = "root"),
        capabilities = setOf(NodeCapability.WORKER),
        routedThrough = parent,
        legacySlot = slot,
    )

    private fun deployment(vararg nodes: DeploymentNode) = Deployment(
        id = "dep-1",
        name = "Fleet",
        topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        entry = HostEndpoint(host = "203.0.113.10", user = "root"),
        storedNodes = nodes.toList(),
    )

    @Test
    fun `the slotted machines are not repeated as rows`() {
        val fleet = deployment(
            node("relay", "203.0.113.10", slot = DeploymentNode.LegacySlot.VPS),
            node("home", "10.8.0.2", parent = "relay", slot = DeploymentNode.LegacySlot.HOME),
        )

        assertTrue(SSHConnectionSettings.additionalNodes(fleet) { null }.isEmpty())
    }

    @Test
    fun `a third machine becomes a row carrying its address and its parent`() {
        val fleet = deployment(
            node("relay", "203.0.113.10", slot = DeploymentNode.LegacySlot.VPS),
            node("home", "10.8.0.2", parent = "relay", slot = DeploymentNode.LegacySlot.HOME),
            node("third", "10.8.0.3", parent = "relay"),
        )

        val rows = SSHConnectionSettings.additionalNodes(fleet) { null }

        assertEquals(1, rows.size)
        assertEquals("third", rows[0].id)
        assertEquals("10.8.0.3", rows[0].host)
        assertEquals(22, rows[0].port)
    }

    /** The parent is named the way the TRANSPORT names it */
    @Test
    fun `a parent that holds a slot is named by that slot`() {
        val fleet = deployment(
            node("relay", "203.0.113.10", slot = DeploymentNode.LegacySlot.VPS),
            node("third", "10.8.0.3", parent = "relay"),
        )

        val row = SSHConnectionSettings.additionalNodes(fleet) { null }.single()

        assertEquals(SSHHostID.VPS, row.parent)
        assertTrue(row.parent?.slot != null, "the entry machine is addressed by slot, not by node id")
    }

    @Test
    fun `a parent without a slot is named by its node id`() {
        val fleet = deployment(
            node("relay", "203.0.113.10", slot = DeploymentNode.LegacySlot.VPS),
            node("third", "10.8.0.3", parent = "relay"),
            node("fourth", "10.8.0.4", parent = "third"),
        )

        val fourth = SSHConnectionSettings.additionalNodes(fleet) { null }.single { it.id == "fourth" }

        assertEquals(SSHHostID.node("third"), fourth.parent)
    }

    @Test
    fun `a machine with no parent is dialled directly`() {
        val fleet = deployment(
            node("relay", "203.0.113.10", slot = DeploymentNode.LegacySlot.VPS),
            node("standalone", "192.168.1.9"),
        )

        assertNull(SSHConnectionSettings.additionalNodes(fleet) { null }.single().parent)
    }

    @Test
    fun `a parent that is not in the fleet leaves the row dialled directly`() {
        val fleet = deployment(
            node("relay", "203.0.113.10", slot = DeploymentNode.LegacySlot.VPS),
            node("orphan", "10.8.0.7", parent = "a-machine-that-was-removed"),
        )

        assertNull(SSHConnectionSettings.additionalNodes(fleet) { null }.single().parent)
    }

    @Test
    fun `the pin is looked up by the id the transport addresses the node with`() {
        val fleet = deployment(
            node("relay", "203.0.113.10", slot = DeploymentNode.LegacySlot.VPS),
            node("third", "10.8.0.3", parent = "relay"),
        )
        val asked = mutableListOf<SSHHostID>()

        val row = SSHConnectionSettings.additionalNodes(fleet) { host ->
            asked += host
            if (host == SSHHostID.node("third")) "ssh-ed25519 AAAApinned" else null
        }.single()

        assertEquals(listOf(SSHHostID.node("third")), asked)
        assertEquals("ssh-ed25519 AAAApinned", row.pinnedHostKey)
    }

    @Test
    fun `a deployment that never grew produces no rows`() {
        val pair = Deployment(
            id = "dep-2",
            name = "Pair",
            topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
            entry = HostEndpoint(host = "203.0.113.10", user = "root"),
        )

        assertTrue(SSHConnectionSettings.additionalNodes(pair) { null }.isEmpty())
    }
}
