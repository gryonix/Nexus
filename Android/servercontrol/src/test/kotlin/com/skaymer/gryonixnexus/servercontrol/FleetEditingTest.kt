package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import java.io.File
import java.nio.file.Files
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class FleetEditingTest {
    private fun pair() = Deployment(
        id = "cccccccc-cccc-cccc-cccc-cccccccccccc",
        name = "B",
        topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        domain = "example.com",
        entry = HostEndpoint(host = "203.0.113.10", user = "root"),
        homeWGAddress = "10.8.0.2",
        services = setOf(ServiceID.NEXTCLOUD, ServiceID.VAULTWARDEN),
    )

    private fun node(id: String, parent: String?, worker: Boolean = true) = DeploymentNode(
        id = id,
        endpoint = HostEndpoint(host = "10.8.0.9", user = "root"),
        capabilities = if (worker) setOf(NodeCapability.WORKER) else setOf(NodeCapability.INGRESS),
        routedThrough = parent,
    )

    @Test
    fun `adding a machine stops the node list being derived`() {
        val base = pair()
        assertNull(base.storedNodes, "a shipped pair stores nothing")

        val relay = base.nodes.first { it.legacySlot == DeploymentNode.LegacySlot.VPS }
        val grown = base.addingNode(node("dddddddd-dddd-dddd-dddd-dddddddddddd", relay.id))

        assertEquals(3, grown.nodes.size)
        assertTrue(grown.storedNodes != null, "the two host fields can no longer say what this is")
    }

    @Test
    fun `a machine with no address is refused`() {
        val error = assertFailsWith<NodeEditException> {
            pair().addingNode(
                DeploymentNode(
                    id = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
                    endpoint = HostEndpoint(host = "  ", user = "root"),
                    capabilities = setOf(NodeCapability.WORKER),
                ),
            )
        }
        assertEquals(NodeEditException.Reason.NO_ADDRESS, error.reason)
    }

    /** The transport would have nothing to jump from */
    @Test
    fun `a machine reached through a stranger is refused`() {
        val error = assertFailsWith<NodeEditException> {
            pair().addingNode(
                node("dddddddd-dddd-dddd-dddd-dddddddddddd", "ffffffff-ffff-ffff-ffff-ffffffffffff"),
            )
        }
        assertEquals(NodeEditException.Reason.UNKNOWN_PARENT, error.reason)
    }

    @Test
    fun `a parent loop is refused`() {
        val a = "11111111-0000-0000-0000-000000000001"
        val b = "11111111-0000-0000-0000-000000000002"
        val relay = pair().nodes.first { it.legacySlot == DeploymentNode.LegacySlot.VPS }
        val withA = pair().addingNode(node(a, relay.id))
        val withB = withA.addingNode(node(b, a))
        val error = assertFailsWith<NodeEditException> { withB.addingNode(node(a, b)) }
        assertEquals(NodeEditException.Reason.PARENT_LOOP, error.reason)
    }

    @Test
    fun `a machine others are reached through cannot be removed`() {
        val relay = pair().nodes.first { it.legacySlot == DeploymentNode.LegacySlot.VPS }
        val error = assertFailsWith<NodeEditException> { pair().removingNode(relay.id) }
        assertEquals(NodeEditException.Reason.STILL_A_PARENT, error.reason)
    }

    /** An install has to have somewhere to land */
    @Test
    fun `the last worker cannot be removed`() {
        val home = pair().nodes.first { it.legacySlot == DeploymentNode.LegacySlot.HOME }
        val error = assertFailsWith<NodeEditException> { pair().removingNode(home.id) }
        assertEquals(NodeEditException.Reason.LAST_WORKER, error.reason)
    }

    @Test
    fun `removing a machine clears the placements that named it`() {
        val relay = pair().nodes.first { it.legacySlot == DeploymentNode.LegacySlot.VPS }
        val extra = "22222222-0000-0000-0000-000000000001"
        val grown = pair().addingNode(node(extra, relay.id))
            .placing(ServiceID.NEXTCLOUD, extra)
        assertEquals(SSHHostID.node(extra), grown.hostRunning(ServiceID.NEXTCLOUD))

        val shrunk = grown.removingNode(extra)
        assertNull(shrunk.placement, "the last placement went with the machine")
        assertEquals(SSHHostID.HOME, shrunk.hostRunning(ServiceID.NEXTCLOUD))
    }

    @Test
    fun `placing null returns a service to the default worker`() {
        val relay = pair().nodes.first { it.legacySlot == DeploymentNode.LegacySlot.VPS }
        val extra = "22222222-0000-0000-0000-000000000002"
        val placed = pair().addingNode(node(extra, relay.id)).placing(ServiceID.NEXTCLOUD, extra)
        val cleared = placed.placing(ServiceID.NEXTCLOUD, null)
        assertNull(cleared.placement)
    }
}

/** Where the ingress sends a request for one service */
class ServiceUpstreamTest {
    private fun pair(services: Set<ServiceID> = setOf(ServiceID.NEXTCLOUD)) = Deployment(
        id = "33333333-0000-0000-0000-000000000001",
        name = "B",
        topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        domain = "example.com",
        entry = HostEndpoint(host = "203.0.113.10", user = "root"),
        homeWGAddress = "10.8.0.2",
        services = services,
    )

    private fun extraWorker(deployment: Deployment, id: String): Deployment {
        val relay = deployment.nodes.first { it.legacySlot == DeploymentNode.LegacySlot.VPS }
        return deployment.addingNode(
            DeploymentNode(
                id = id,
                endpoint = HostEndpoint(host = "10.8.0.3", user = "root"),
                capabilities = setOf(NodeCapability.WORKER),
                routedThrough = relay.id,
            ),
        ).placing(ServiceID.NEXTCLOUD, id)
    }

    @Test
    fun `a worker that serves its own traffic stays local`() {
        assertEquals(
            ServiceUpstream.Local,
            pair().upstream(ServiceID.NEXTCLOUD, "cloud.example.com"),
        )
    }

    /** The mesh hop carries an explicit server name */
    @Test
    fun `a worker behind the ingress is reached over the mesh, by name`() {
        val extra = "33333333-0000-0000-0000-000000000009"
        val grown = extraWorker(pair(setOf(ServiceID.NEXTCLOUD, ServiceID.HEADSCALE)), extra)
        assertEquals(
            ServiceUpstream.Mesh(extra, "cloud.example.com"),
            grown.upstream(ServiceID.NEXTCLOUD, "cloud.example.com"),
        )
    }

    @Test
    fun `a second worker with no mesh is a named problem`() {
        val extra = "33333333-0000-0000-0000-00000000000a"
        val grown = extraWorker(pair(), extra)
        assertFalse(grown.hasMesh)
        assertEquals(
            listOf(PlacementProblem.NeedsMeshToReachWorker(ServiceID.NEXTCLOUD)),
            grown.placementProblems(),
        )
    }

    @Test
    fun `a one-worker deployment has no placement problems`() {
        assertTrue(pair().placementProblems().isEmpty())
    }

    @Test
    fun `a mesh answers the problem for every service at once`() {
        val extra = "33333333-0000-0000-0000-00000000000b"
        val grown = extraWorker(pair(setOf(ServiceID.NEXTCLOUD, ServiceID.TAILSCALE_NODE)), extra)
        assertTrue(grown.hasMesh)
        assertTrue(grown.placementProblems().isEmpty())
    }
}

class HostKeyPinAccountsTest {
    @Test
    fun `a slot resolves to its derived node account`() {
        val deployment = "6D3E0000-DE40-4000-8000-000000000002"
        assertEquals(
            "hostkey-$deployment-6D3E0000-DE40-4000-8000-000000000003",
            HostKeyPinAccounts.current(deployment, DeploymentNode.LegacySlot.VPS),
        )
        assertEquals(
            "hostkey-$deployment-6D3E0000-DE40-4000-8000-000000000000",
            HostKeyPinAccounts.current(deployment, DeploymentNode.LegacySlot.HOME),
        )
    }

    @Test
    fun `the legacy account is named by slot`() {
        val deployment = "6D3E0000-DE40-4000-8000-000000000002"
        assertEquals(
            "hostkey-$deployment-vps",
            HostKeyPinAccounts.legacy(deployment, DeploymentNode.LegacySlot.VPS),
        )
        assertTrue(
            HostKeyPinAccounts.legacy(deployment, DeploymentNode.LegacySlot.VPS) !=
                HostKeyPinAccounts.current(deployment, DeploymentNode.LegacySlot.VPS),
        )
    }
}

class FileDeploymentStoreTest {
    private fun deployment(id: String, name: String) = Deployment(
        id = id,
        name = name,
        topology = Topology.SINGLE_HOST,
        domain = "example.com",
        entry = HostEndpoint(host = "203.0.113.4", user = "admin"),
    )

    @Test
    fun `a missing file is an empty fleet, not a failure`() {
        val dir = Files.createTempDirectory("fleet").toFile()
        val store = FileDeploymentStore(File(dir, "deployments.json"))
        assertEquals(emptyList(), store.load())
    }

    @Test
    fun `what is saved comes back, and upsert replaces by id`() {
        val dir = Files.createTempDirectory("fleet").toFile()
        val store = FileDeploymentStore(File(dir, "deployments.json"))
        val one = deployment("44444444-0000-0000-0000-000000000001", "one")

        store.upsert(one)
        store.upsert(deployment("44444444-0000-0000-0000-000000000002", "two"))
        assertEquals(listOf("one", "two"), store.load().map { it.name })

        store.upsert(one.copy(name = "renamed"))
        assertEquals(listOf("renamed", "two"), store.load().map { it.name })

        store.remove("44444444-0000-0000-0000-000000000001")
        assertEquals(listOf("two"), store.load().map { it.name })
    }

    @Test
    fun `saving leaves no staging file behind`() {
        val dir = Files.createTempDirectory("fleet").toFile()
        val store = FileDeploymentStore(File(dir, "deployments.json"))
        store.save(listOf(deployment("44444444-0000-0000-0000-000000000003", "one")))
        assertEquals(listOf("deployments.json"), dir.list()!!.sorted())
    }
}
