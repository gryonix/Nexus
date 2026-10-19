package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.servercontrol.HealthLevel
import com.skaymer.gryonixnexus.servercontrol.ServiceControlRoute
import com.skaymer.gryonixnexus.servercontrol.ServiceControlRouting
import com.skaymer.gryonixnexus.servercontrol.ServicePowerAction
import gryonixnexusd.v1.Container
import gryonixnexusd.v1.Service
import gryonixnexusd.v1.ServiceAction
import gryonixnexusd.v1.ServiceOperationEvent
import gryonixnexusd.v1.ServiceOperationPhase
import gryonixnexusd.v1.ServiceStatusResponse
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class AgentCommandRunnerTest {
    private fun service(id: ServiceID): ManagedService = checkNotNull(ServiceRegistry.service(id))

    private fun runner(transport: FakeAgentTransport) = AgentCommandRunner(AgentClient(transport))

    private fun containers(vararg pairs: Pair<String, String>) =
        pairs.map { (name, state) -> Container(name = name, state = state) }

    @Test
    fun `the route uses the agent only when it is usable from this device`() {
        assertEquals(
            ServiceControlRoute.AGENT,
            ServiceControlRouting.route(usesAgent = true, agentTransportAvailable = true),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            ServiceControlRouting.route(usesAgent = true, agentTransportAvailable = false),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            ServiceControlRouting.route(usesAgent = false, agentTransportAvailable = true),
        )
    }

    @Test
    fun `every VPN protocol addresses the aggregate service`() {
        for (id in ServiceID.VPN_PROTOCOLS + ServiceID.VPN_PANEL) {
            assertEquals("vpn", AgentCommandRunner.agentID(service(id)), id.rawValue)
        }
    }

    @Test
    fun `status sends the catalog id on the ServiceStatus path`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Control/ServiceStatus",
            ServiceStatusResponse(
                service = Service(id = "nextcloud", containers = containers("nextcloud-app" to "running")),
                installed = true,
            ),
        )

        val statuses = runner(transport).status(service(ServiceID.NEXTCLOUD))

        assertEquals(listOf("/gryonixnexusd.v1.Control/ServiceStatus"), transport.paths)
        assertEquals(listOf("nextcloud-app"), statuses.map { it.name })
        assertEquals(HealthLevel.OK, statuses.first().health)
    }

    @Test
    fun `not installed is an empty list, not a throw`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Control/ServiceStatus", ServiceStatusResponse(installed = false))

        assertEquals(emptyList(), runner(transport).status(service(ServiceID.NEXTCLOUD)))
    }

    @Test
    fun `a restart sends the typed action and returns the status read after it`() = runTest {
        val transport = FakeAgentTransport()
        transport.stream(
            "Control/ControlService",
            ServiceOperationEvent(
                phase = ServiceOperationPhase.SERVICE_OPERATION_PHASE_STARTED,
                service_id = "nextcloud",
            ),
            ServiceOperationEvent(
                phase = ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS,
                text = "restarting",
            ),
            ServiceOperationEvent(
                phase = ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED,
                service = Service(containers = containers("nextcloud-app" to "running")),
            ),
        )

        val progress = mutableListOf<String>()
        val statuses = runner(transport).power(
            ServicePowerAction.RESTART,
            service(ServiceID.NEXTCLOUD),
        ) { progress += it }

        assertEquals(listOf("nextcloud-app"), statuses.map { it.name })
        assertEquals(listOf("restarting\n"), progress)
        val request = ServiceOperationRequestDecoder.action(transport.calls.first().second)
        assertEquals(ServiceAction.SERVICE_ACTION_RESTART, request)
    }

    @Test
    fun `stop and start map to their own wire actions`() = runTest {
        for ((action, wire) in listOf(
            ServicePowerAction.STOP to ServiceAction.SERVICE_ACTION_STOP,
            ServicePowerAction.START to ServiceAction.SERVICE_ACTION_START,
        )) {
            val transport = FakeAgentTransport()
            transport.stream(
                "Control/ControlService",
                ServiceOperationEvent(phase = ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED),
            )
            runner(transport).power(action, service(ServiceID.NEXTCLOUD))
            assertEquals(wire, ServiceOperationRequestDecoder.action(transport.calls.first().second))
        }
    }

    /** The two-channel rule */
    @Test
    fun `a failed run throws and carries the final status with it`() = runTest {
        val transport = FakeAgentTransport()
        transport.streamThenFail(
            "Control/ControlService",
            AgentError.Rpc("internal", "docker exited 1"),
            ServiceOperationEvent(
                phase = ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED,
                service = Service(containers = containers("nextcloud-app" to "exited")),
            ),
        )

        val error = assertFailsWith<AgentControlError.OperationFailed> {
            runner(transport).power(ServicePowerAction.RESTART, service(ServiceID.NEXTCLOUD))
        }
        assertEquals(listOf("nextcloud-app"), error.status.map { it.name })
        assertEquals(HealthLevel.CRITICAL, error.status.first().health)
        assertEquals("docker exited 1", error.message)
    }

    @Test
    fun `a refusal before the action keeps its own Connect code`() = runTest {
        val transport = FakeAgentTransport()
        transport.refuse("Control/ControlService", code = "not_found", text = "no such service")

        val error = assertFailsWith<AgentError.Rpc> {
            runner(transport).power(ServicePowerAction.RESTART, service(ServiceID.NEXTCLOUD))
        }
        assertEquals("not_found", error.code)
    }

    @Test
    fun `an unknown phase from a newer agent is ignored`() = runTest {
        val transport = FakeAgentTransport()
        transport.stream(
            "Control/ControlService",
            ServiceOperationEvent(phase = ServiceOperationPhase.SERVICE_OPERATION_PHASE_UNSPECIFIED),
            ServiceOperationEvent(
                phase = ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED,
                service = Service(containers = containers("app" to "running")),
            ),
        )
        val statuses = runner(transport).power(ServicePowerAction.START, service(ServiceID.NEXTCLOUD))
        assertEquals(listOf("app"), statuses.map { it.name })
    }

    @Test
    fun `a container state becomes the vocabulary the dashboard reads`() {
        fun status(state: String, health: String = "") =
            AgentCommandRunner.containerStatus(Container(name = "c", state = state, health = health))

        assertEquals("Up", status("running").status)
        assertEquals(HealthLevel.OK, status("running").health)
        assertEquals("Up (healthy)", status("running", "healthy").status)
        assertEquals(HealthLevel.CRITICAL, status("exited").health)
        assertEquals(HealthLevel.CRITICAL, status("dead").health)
        assertEquals("Restarting", status("restarting").status)
        assertEquals(HealthLevel.WARNING, status("restarting").health)
        assertEquals("Unknown", status("").status)
        assertEquals(HealthLevel.WARNING, status("").health)
    }

    @Test
    fun `a service the agent does not model is refused before any call`() = runTest {
        val transport = FakeAgentTransport()
        val unmodelled = object : ManagedService by service(ServiceID.NEXTCLOUD) {
            override val id: ServiceID = ServiceID("no-such-service")
            override val displayName: String = "Nothing"
        }
        assertFailsWith<AgentControlError.UnsupportedService> {
            runner(transport).status(unmodelled)
        }
        assertTrue(transport.calls.isEmpty())
    }
}

internal object ServiceOperationRequestDecoder {
    fun action(request: ByteArray): ServiceAction =
        gryonixnexusd.v1.ControlServiceRequest.ADAPTER.decode(request).action
}
