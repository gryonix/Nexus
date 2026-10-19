package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.Topology
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Test

class ServiceControlRoutingTest {
    private fun deployment(usesAgent: Boolean = false) = Deployment(
        id = "55555555-5555-5555-5555-555555555555",
        name = "Test",
        topology = Topology.SINGLE_HOST,
        domain = "example.com",
        entry = HostEndpoint(host = "203.0.113.4", user = "admin"),
        services = setOf(ServiceID.NEXTCLOUD),
        usesAgent = usesAgent,
    )

    private fun service(id: ServiceID): ManagedService = checkNotNull(ServiceRegistry.service(id))

    @Test
    fun `a deployment is on SSH unless it explicitly has an agent`() {
        assertFalse(deployment().usesAgent)
        assertEquals(
            ServiceControlRoute.SSH,
            ServiceControlRouting.route(deployment().usesAgent, agentTransportAvailable = true),
        )
        assertEquals(
            ServiceControlRoute.AGENT,
            ServiceControlRouting.route(
                deployment(usesAgent = true).usesAgent,
                agentTransportAvailable = true,
            ),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            ServiceControlRouting.route(usesAgent = true, agentTransportAvailable = false),
        )
    }

    @Test
    fun `the SSH route sends the same catalog commands and re-reads the status`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("docker compose -p nextcloud restart")
        runner.stub(
            "docker compose -p nextcloud ps",
            stdout = """
            NAME            IMAGE             COMMAND    SERVICE   CREATED       STATUS         PORTS
            nextcloud-app   nextcloud:apache  "apache"   app       2 hours ago   Up 2 hours     127.0.0.1:8081->80/tcp
            """.trimIndent(),
        )
        val control = SSHServiceControl(runner, deployment())

        val statuses = control.power(ServicePowerAction.RESTART, service(ServiceID.NEXTCLOUD))

        assertEquals(listOf("nextcloud-app"), statuses.map { it.name })
        assertEquals(
            listOf(
                "sudo docker compose -p nextcloud restart",
                "sudo docker compose -p nextcloud ps",
            ),
            runner.calls.map { it.command },
        )
    }
}
