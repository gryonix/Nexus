package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.servercontrol.PurgeOptions
import com.skaymer.gryonixnexus.servercontrol.RemovalScope
import com.skaymer.gryonixnexus.servercontrol.ServiceControlRoute
import com.skaymer.gryonixnexus.servercontrol.ServiceRemovalRouting
import gryonixnexusd.v1.Container
import gryonixnexusd.v1.RemoveServiceRequest
import gryonixnexusd.v1.Service
import gryonixnexusd.v1.ServiceOperationPhase
import gryonixnexusd.v1.ServiceStatusResponse
import gryonixnexusd.v1.UninstallEvent
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of `AgentServiceRemovalTests` */
class AgentServiceRemovalTest {
    private fun service(id: ServiceID): ManagedService = checkNotNull(ServiceRegistry.service(id))

    private fun event(
        phase: ServiceOperationPhase,
        text: String = "",
        installed: Boolean? = null,
        containers: List<Container> = emptyList(),
    ) = UninstallEvent(
        phase = phase,
        text = text,
        status = installed?.let {
            ServiceStatusResponse(
                installed = it,
                service = containers.takeIf { c -> c.isNotEmpty() }?.let { c -> Service(containers = c) },
            )
        },
    )

    // ------------------------------------------------------------- Routing

    @Test
    fun `only a single service ever routes to the agent`() {
        assertEquals(
            ServiceControlRoute.SSH,
            ServiceRemovalRouting.route(RemovalScope.EVERYTHING, usesAgent = true, agentTransportAvailable = true),
        )
        assertEquals(
            ServiceControlRoute.AGENT,
            ServiceRemovalRouting.route(RemovalScope.SERVICE, usesAgent = true, agentTransportAvailable = true),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            ServiceRemovalRouting.route(RemovalScope.SERVICE, usesAgent = true, agentTransportAvailable = false),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            ServiceRemovalRouting.route(RemovalScope.SERVICE, usesAgent = false, agentTransportAvailable = true),
        )
    }

    // ------------------------------------------------------------- Removal

    @Test
    fun `a successful removal sends purge flags and returns the streamed log`() = runTest {
        val transport = FakeAgentTransport()
        transport.stream(
            "Uninstall/RemoveService",
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_STARTED),
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS, text = "stopping containers"),
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED, installed = false),
        )

        val chunks = mutableListOf<String>()
        val log = AgentServiceRemoval(AgentClient(transport))
            .remove(service(ServiceID.NEXTCLOUD), PurgeOptions(data = true, backups = false)) {
                chunks += it
            }

        assertEquals(listOf("/gryonixnexusd.v1.Uninstall/RemoveService"), transport.paths)
        val sent = RemoveServiceRequest.ADAPTER.decode(transport.calls.first().second)
        assertEquals("nextcloud", sent.service_id)
        assertTrue(sent.purge_data)
        assertFalse(sent.purge_backups)
        assertEquals(listOf("stopping containers\n"), chunks)
        assertTrue(log.contains("stopping containers"), log)
    }

    @Test
    fun `a failed removal throws and carries the re-read status`() = runTest {
        val transport = FakeAgentTransport()
        transport.streamThenFail(
            "Uninstall/RemoveService",
            AgentError.Rpc("internal", "could not remove the compose project"),
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS, text = "stopping containers"),
            event(
                ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED,
                installed = true,
                containers = listOf(Container(name = "nextcloud-app", state = "running")),
            ),
        )

        val error = runCatching {
            AgentServiceRemoval(AgentClient(transport))
                .remove(service(ServiceID.NEXTCLOUD), PurgeOptions.NONE) { }
        }.exceptionOrNull()

        assertTrue(error is AgentControlError.OperationFailed, "got $error")
        assertEquals(AgentError.Rpc("internal", "could not remove the compose project"), error.underlying)
        assertEquals(listOf("nextcloud-app"), error.status.map { it.name })
    }

    @Test
    fun `a refusal before anything ran keeps its own connect code`() = runTest {
        val refusal = AgentError.Rpc("not_found", "no such service")
        val transport = FakeAgentTransport()
        transport.fail("Uninstall/RemoveService", refusal)

        val error = runCatching {
            AgentServiceRemoval(AgentClient(transport))
                .remove(service(ServiceID.IMMICH), PurgeOptions.NONE) { }
        }.exceptionOrNull()

        assertEquals(refusal, error)
    }
}
