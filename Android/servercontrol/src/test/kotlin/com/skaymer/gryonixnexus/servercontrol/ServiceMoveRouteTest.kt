package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.Topology
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class ServiceMoveRouteTest {
    private fun single(agent: Boolean = true) = Deployment(
        id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", name = "A", topology = Topology.SINGLE_HOST,
        domain = "example.com", entry = HostEndpoint(host = "203.0.113.10", user = "root"),
        services = setOf(ServiceID.NEXTCLOUD, ServiceID.VAULTWARDEN), usesAgent = agent,
    )

    private fun extra(id: String = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", host: String = "10.0.0.7") = DeploymentNode(
        id = id, name = "Second", endpoint = HostEndpoint(host = host, user = "admin"),
        capabilities = setOf(NodeCapability.WORKER),
    )

    private fun ready(result: MoveRouteResult) = (result as MoveRouteResult.Ready).route

    @Test
    fun `the front of a single host is that host`() {
        val deployment = single()
        assertEquals(deployment.nodes[0].id, deployment.frontNode?.id)
    }

    @Test
    fun `the front of a relay is the home half that answers its own traffic`() {
        val relay = single().copy(topology = Topology.VPS_RELAY_WITH_HOME_BACKEND, homeWGAddress = "10.8.0.2")
        assertEquals(DeploymentNode.LegacySlot.HOME, relay.frontNode?.legacySlot)
    }

    @Test
    fun `moving off the front dials the other machine and moving back serves it locally`() {
        val second = extra()
        var deployment = single().addingNode(second)
        val out = ready(deployment.moveRoute(ServiceID.NEXTCLOUD, second.id))
        assertEquals(deployment.nodes[0].id, out.source.id)
        assertNull(out.sourceEntryAddress)
        assertEquals("10.0.0.7", out.targetEntryAddress)

        deployment = deployment.placing(ServiceID.NEXTCLOUD, second.id)
        val back = ready(deployment.moveRoute(ServiceID.NEXTCLOUD, deployment.nodes[0].id))
        assertEquals("10.0.0.7", back.sourceEntryAddress)
        assertNull(back.targetEntryAddress)
    }

    @Test
    fun `moving between two machines behind the front dials both`() {
        val second = extra()
        val third = extra("cccccccc-cccc-cccc-cccc-cccccccccccc", "10.0.0.8")
        val deployment = single().addingNode(second).addingNode(third).placing(ServiceID.NEXTCLOUD, second.id)
        val route = ready(deployment.moveRoute(ServiceID.NEXTCLOUD, third.id))
        assertEquals("10.0.0.7", route.sourceEntryAddress)
        assertEquals("10.0.0.8", route.targetEntryAddress)
    }

    @Test
    fun `the refusals name their reason`() {
        val second = extra()
        val deployment = single().addingNode(second)
        fun reason(result: MoveRouteResult) = (result as MoveRouteResult.Refused).reason
        assertEquals(ServiceMoveRefusal.SAME_MACHINE, reason(deployment.moveRoute(ServiceID.NEXTCLOUD, deployment.nodes[0].id)))
        assertEquals(ServiceMoveRefusal.UNKNOWN_MACHINE, reason(deployment.moveRoute(ServiceID.NEXTCLOUD, "nope")))
        assertEquals(ServiceMoveRefusal.NO_AGENT, reason(single(agent = false).moveRoute(ServiceID.NEXTCLOUD, second.id)))
        val relayOnly = DeploymentNode(
            id = "dddddddd-dddd-dddd-dddd-dddddddddddd",
            endpoint = HostEndpoint(host = "1.2.3.4", user = "r"),
            capabilities = setOf(NodeCapability.INGRESS),
        )
        val withRelay = deployment.addingNode(relayOnly)
        assertEquals(ServiceMoveRefusal.TARGET_DOES_NOT_RUN_SERVICES, reason(withRelay.moveRoute(ServiceID.NEXTCLOUD, relayOnly.id)))
    }

    @Test
    fun `a pure relay with no worker that answers its own traffic has no front`() {
        fun node(id: String, host: String, caps: Set<NodeCapability>) =
            DeploymentNode(id = id, endpoint = HostEndpoint(host = host, user = "r"), capabilities = caps)
        val other = node("33333333-3333-3333-3333-333333333333", "10.0.0.3", setOf(NodeCapability.WORKER))
        val deployment = single().copy(
            storedNodes = listOf(
                node("11111111-1111-1111-1111-111111111111", "1.2.3.4", setOf(NodeCapability.INGRESS)),
                node("22222222-2222-2222-2222-222222222222", "10.0.0.2", setOf(NodeCapability.WORKER)),
                other,
            ),
        )
        assertNull(deployment.frontNode)
        assertEquals(ServiceMoveRefusal.NO_FRONT, (deployment.moveRoute(ServiceID.NEXTCLOUD, other.id) as MoveRouteResult.Refused).reason)
    }

    @Test
    fun `only services with a site a backup and no other ports move`() {
        val context = single().serviceContext
        fun movable(id: ServiceID) = ServiceRegistry.service(id)?.let { ServiceMovePolicy.isMovable(it, context) } ?: false
        assertTrue(movable(ServiceID.NEXTCLOUD))
        for (stays in listOf(ServiceID.AUTHELIA, ServiceID.ADGUARD_HOME, ServiceID.PIHOLE, ServiceID.MAILCOW, ServiceID.WIREGUARD_VPN, ServiceID.MINECRAFT_JAVA)) {
            assertFalse(movable(stays), stays.rawValue)
        }
    }
}
