package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of `NodeDerivedQuestionsTests` */
class NodeDerivedQuestionsTest {
    private fun single() = Deployment(
        id = "11111111-1111-1111-1111-111111111111",
        name = "A",
        topology = Topology.SINGLE_HOST,
        domain = "example.com",
        entry = HostEndpoint(host = "203.0.113.10", user = "root"),
    )

    private fun pair() = Deployment(
        id = "22222222-2222-2222-2222-222222222222",
        name = "B",
        topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        domain = "example.com",
        entry = HostEndpoint(host = "203.0.113.10", port = 2222, user = "admin"),
        homeWGAddress = "10.8.0.2",
    )

    private fun thirdWorker(deployment: Deployment) = DeploymentNode(
        id = "33333333-3333-3333-3333-333333333333",
        name = "Second worker",
        endpoint = HostEndpoint(host = "10.8.0.3", port = 2222, user = "admin"),
        capabilities = setOf(NodeCapability.WORKER),
        routedThrough = deployment.ingressNode?.id,
    )

    // MARK: - The two shapes that are on disk today

    @Test
    fun `a single host answers exactly as the enum branch did`() {
        val deployment = single()
        assertFalse(deployment.isMultiHost)
        assertFalse(deployment.hasRelayIngress, "one machine terminating AND running is not a relay")
        assertFalse(deployment.hasHomeHost)
        assertEquals(SSHHostID.VPS, deployment.servicesHost)
        assertEquals(listOf(SSHHostID.VPS), deployment.workerHosts)
    }

    @Test
    fun `the relay pair answers exactly as the enum branch did`() {
        val deployment = pair()
        assertTrue(deployment.isMultiHost)
        assertTrue(deployment.hasRelayIngress)
        assertTrue(deployment.hasHomeHost)
        assertEquals(SSHHostID.HOME, deployment.servicesHost)
        assertEquals(listOf(SSHHostID.HOME), deployment.workerHosts)
    }

    @Test
    fun `a pair without a tunnel address has no home host`() {
        assertFalse(pair().copy(homeWGAddress = null).hasHomeHost)
        assertFalse(pair().copy(homeWGAddress = "").hasHomeHost)
    }

    // MARK: - The shapes the enum could not express

    /** Two workers and no relay: multi-host, but nothing is ingress-only */
    @Test
    fun `two workers with no relay are multi-host without a relay ingress`() {
        val base = single()
        val extra = DeploymentNode(
            id = "44444444-4444-4444-4444-444444444444",
            endpoint = HostEndpoint(host = "192.168.1.50", user = "root"),
            capabilities = setOf(NodeCapability.WORKER),
        )
        val deployment = base.copy(storedNodes = base.derivedNodes + extra)

        assertTrue(deployment.isMultiHost)
        assertFalse(deployment.hasRelayIngress, "no machine here is ingress-only")
        assertFalse(deployment.hasHomeHost, "a node that routes through nobody is not behind anything")
        assertEquals(SSHHostID.VPS, deployment.servicesHost, "the first worker still answers, unchanged")
        assertEquals(listOf(SSHHostID.VPS, SSHHostID.node(extra.id)), deployment.workerHosts)
    }

    /** A third worker behind the relay */
    @Test
    fun `a third worker joins workerHosts without moving the default host`() {
        val base = pair()
        val extra = thirdWorker(base)
        val deployment = base.copy(storedNodes = base.derivedNodes + extra)

        assertTrue(deployment.isMultiHost)
        assertTrue(deployment.hasRelayIngress)
        assertTrue(deployment.hasHomeHost)
        assertEquals(SSHHostID.HOME, deployment.servicesHost,
                     "adding a machine must not move where unplaced work goes")
        assertEquals(listOf(SSHHostID.HOME, SSHHostID.node(extra.id)), deployment.workerHosts)
    }

    @Test
    fun `a machine added after the slots is addressed by its own id`() {
        val extra = thirdWorker(pair())
        assertNull(extra.legacySlot)
        assertEquals(SSHHostID.node(extra.id), extra.sshHost)
        assertNull(extra.sshHost.slot, "nothing keyed by slot may claim to have found one")
    }

    @Test
    fun `only a placement moves a service onto the third machine`() {
        val base = pair()
        val extra = thirdWorker(base)
        val deployment = base.copy(
            storedNodes = base.derivedNodes + extra,
            services = setOf(ServiceID.DOCKER_MAILSERVER, ServiceID.VAULTWARDEN),
        )

        assertEquals(SSHHostID.HOME, deployment.hostRunning(ServiceID.DOCKER_MAILSERVER),
                     "an unplaced service stays on the machine it has always been on")

        val placed = deployment.copy(
            placement = ServicePlacement(mapOf(ServiceID.DOCKER_MAILSERVER.rawValue to extra.id)),
        )
        assertEquals(SSHHostID.node(extra.id), placed.hostRunning(ServiceID.DOCKER_MAILSERVER))
        assertEquals(SSHHostID.HOME, placed.hostRunning(ServiceID.VAULTWARDEN),
                     "placing one service must not move the others")
    }

    @Test
    fun `a placement naming the relay falls back to a worker`() {
        val base = pair()
        val deployment = base.copy(
            services = setOf(ServiceID.DOCKER_MAILSERVER),
            placement = ServicePlacement(
                mapOf(ServiceID.DOCKER_MAILSERVER.rawValue to base.ingressNode!!.id),
            ),
        )
        assertEquals(SSHHostID.HOME, deployment.hostRunning(ServiceID.DOCKER_MAILSERVER))
    }

    // MARK: - Teardown order with three machines

    @Test
    fun `both workers are torn down before the relay they are reached through`() {
        val base = pair()
        val extra = thirdWorker(base)
        val deployment = base.copy(storedNodes = base.derivedNodes + extra)

        val order = deployment.teardownOrder.map { it.id }
        val relayIndex = order.indexOf(deployment.ingressNode!!.id)
        assertEquals(3, order.size)
        assertTrue(relayIndex >= 0)
        for (worker in deployment.nodes.filter { it.runsServices }) {
            val index = order.indexOf(worker.id)
            assertTrue(index in 0 until relayIndex,
                       "a worker cleaned after its relay is unreachable with its data still on it")
        }
    }
}
