package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ServiceCommand
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import kotlin.time.Duration.Companion.seconds
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class HostRoutingTest {
    private fun pair() = Deployment(
        id = "22222222-2222-2222-2222-222222222222",
        name = "B",
        topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        domain = "example.com",
        entry = HostEndpoint(host = "203.0.113.10", user = "root"),
        homeWGAddress = "10.8.0.2",
        services = setOf(ServiceID.VAULTWARDEN, ServiceID.NEXTCLOUD, ServiceID.DOCKER_MAILSERVER),
    )

    @Test
    fun `with one worker every service answers the services host`() {
        val deployment = pair()
        for (service in deployment.services) {
            assertEquals(deployment.servicesHost, deployment.hostRunning(service))
        }
        assertEquals(SSHHostID.HOME, deployment.servicesHost)
    }

    @Test
    fun `a placed service answers its own machine`() {
        val base = pair()
        val entry = base.nodes.first { it.legacySlot == DeploymentNode.LegacySlot.VPS }
        val third = DeploymentNode(
            id = "33333333-3333-3333-3333-333333333333",
            endpoint = HostEndpoint(host = "10.8.0.3", user = "root"),
            capabilities = setOf(NodeCapability.WORKER),
            routedThrough = entry.id,
        )
        val deployment = base.copy(
            storedNodes = base.nodes + third,
            placement = ServicePlacement(mapOf(ServiceID.NEXTCLOUD.rawValue to third.id)),
        )

        assertEquals(SSHHostID.node(third.id), deployment.hostRunning(ServiceID.NEXTCLOUD))
        // And only that one moved.
        assertEquals(SSHHostID.HOME, deployment.hostRunning(ServiceID.VAULTWARDEN))
        assertEquals(SSHHostID.HOME, deployment.hostRunning(ServiceID.DOCKER_MAILSERVER))
    }

    @Test
    fun `a stale placement falls back to a worker`() {
        val deployment = pair().let {
            it.copy(
                placement = ServicePlacement(
                    mapOf(ServiceID.NEXTCLOUD.rawValue to "44444444-4444-4444-4444-444444444444"),
                ),
            )
        }
        assertEquals(deployment.servicesHost, deployment.hostRunning(ServiceID.NEXTCLOUD))
    }

    @Test
    fun `the ingress-only machine is never the answer`() {
        val base = pair()
        val entry = base.nodes.first { it.legacySlot == DeploymentNode.LegacySlot.VPS }
        val deployment = base.copy(
            placement = ServicePlacement(mapOf(ServiceID.NEXTCLOUD.rawValue to entry.id)),
        )
        assertEquals(SSHHostID.HOME, deployment.hostRunning(ServiceID.NEXTCLOUD))
    }

    @Test
    fun `a host-wide question addresses every worker`() {
        val base = pair()
        val entry = base.nodes.first { it.legacySlot == DeploymentNode.LegacySlot.VPS }
        val third = DeploymentNode(
            id = "33333333-3333-3333-3333-333333333333",
            endpoint = HostEndpoint(host = "10.8.0.3", user = "root"),
            capabilities = setOf(NodeCapability.WORKER),
            routedThrough = entry.id,
        )

        assertEquals(listOf(SSHHostID.HOME), base.workerHosts)
        assertEquals(
            listOf(SSHHostID.HOME, SSHHostID.node(third.id)),
            base.copy(storedNodes = base.nodes + third).workerHosts,
        )
    }

    @Test
    fun `a single host answers for itself`() {
        val single = pair().copy(topology = Topology.SINGLE_HOST, homeWGAddress = null)
        assertEquals(SSHHostID.VPS, single.servicesHost)
        assertEquals(listOf(SSHHostID.VPS), single.workerHosts)
        assertEquals(SSHHostID.VPS, single.hostRunning(ServiceID.NEXTCLOUD))
    }

    @Test
    fun `each timeout class reads its own field`() {
        val timeouts = OperationTimeouts(
            quickSeconds = 5,
            restartSeconds = 60,
            serviceRestartSeconds = 90,
            longSeconds = 900,
        )
        assertEquals(5.seconds, timeouts.duration(ServiceCommand.TimeoutClass.QUICK))
        assertEquals(90.seconds, timeouts.duration(ServiceCommand.TimeoutClass.RESTART))
        assertEquals(900.seconds, timeouts.duration(ServiceCommand.TimeoutClass.LONG))
    }
}
