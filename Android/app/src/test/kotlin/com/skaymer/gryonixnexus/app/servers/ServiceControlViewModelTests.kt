package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.ContainerStatus
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.ExecChunk
import com.skaymer.gryonixnexus.servercontrol.ExecResult
import com.skaymer.gryonixnexus.servercontrol.HealthLevel
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.ServiceControlRoute
import com.skaymer.gryonixnexus.servercontrol.ServiceControlling
import com.skaymer.gryonixnexus.servercontrol.ServicePowerAction
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

/** Managing the services of one server from this app */
class ServiceControlViewModelTests {
    private val adguard = ServiceID.ADGUARD_HOME
    private val forgejo = ServiceID.FORGEJO

    private fun server(services: Set<ServiceID> = setOf(adguard, forgejo)) = Deployment(
        id = "S-1",
        name = "middle",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
        services = services,
    )

    private object Unused : SSHCommandRunner {
        override suspend fun run(command: String, host: SSHHostID, timeout: Duration): ExecResult =
            error("the rules must not need a transport")
        override fun stream(command: String, host: SSHHostID, timeout: Duration): Flow<ExecChunk> = emptyFlow()
        override suspend fun fireAndForget(command: String, host: SSHHostID) = Unit
        override suspend fun disconnect() = Unit
    }

    /** Management that answers from a script */
    private class Scripted(
        private val statuses: List<Result<List<ContainerStatus>>>,
    ) : ServiceControlling {
        val asked = mutableListOf<String>()
        var reads = 0

        override suspend fun status(service: ManagedService): List<ContainerStatus> {
            asked += "status:${service.id.rawValue}"
            val answer = statuses[minOf(reads, statuses.size - 1)]
            reads += 1
            return answer.getOrThrow()
        }

        override suspend fun power(
            action: ServicePowerAction,
            service: ManagedService,
            onProgress: (String) -> Unit,
        ): List<ContainerStatus> {
            asked += "${action.rawValue}:${service.id.rawValue}"
            val answer = statuses[minOf(reads, statuses.size - 1)]
            reads += 1
            return answer.getOrThrow()
        }
    }

    private fun model(
        scope: CoroutineScope,
        control: Scripted,
        released: MutableList<String> = mutableListOf(),
    ) = ServiceControlViewModel(
        scope = scope,
        runners = { Unused },
        release = { released += it.id },
        control = { _, _ -> control },
    )

    // ------------------------------------------------------------- Reading

    @Test
    fun `each installed service is asked about on its own`() = runTest(StandardTestDispatcher()) {
        val control = Scripted(listOf(Result.success(listOf(ContainerStatus("adguardhome", "Up 2 days")))))
        val model = model(CoroutineScope(coroutineContext), control)
        model.refresh(server())
        runCurrent()

        assertEquals(listOf("status:adguard-home", "status:forgejo"), control.asked)
        assertEquals(HealthLevel.OK, model.states.value.getValue(adguard).containers.single().health)
        model.stop()
    }

    @Test
    fun `nothing is asked about a service the server does not have`() = runTest(StandardTestDispatcher()) {
        val control = Scripted(listOf(Result.success(emptyList())))
        val model = model(CoroutineScope(coroutineContext), control)
        model.refresh(server(services = setOf(adguard)))
        runCurrent()

        assertEquals(listOf("status:adguard-home"), control.asked)
        model.stop()
    }

    /** One failing service is one row */
    @Test
    fun `a failing service does not blank its neighbours`() = runTest(StandardTestDispatcher()) {
        val control = object : ServiceControlling {
            override suspend fun status(service: ManagedService): List<ContainerStatus> =
                if (service.id == adguard) throw RuntimeException("no such container")
                else listOf(ContainerStatus("forgejo", "Up 2 days"))
            override suspend fun power(
                action: ServicePowerAction,
                service: ManagedService,
                onProgress: (String) -> Unit,
            ): List<ContainerStatus> = error("not used")
        }
        val released = mutableListOf<String>()
        val model = ServiceControlViewModel(
            scope = CoroutineScope(coroutineContext),
            runners = { Unused },
            release = { released += it.id },
            control = { _, _ -> control },
        )
        model.refresh(server())
        runCurrent()

        assertEquals("no such container", model.states.value.getValue(adguard).errorMessage)
        assertEquals(listOf("S-1"), released)
        assertEquals(
            HealthLevel.OK,
            model.states.value.getValue(forgejo).containers.single().health,
            "the healthy neighbour keeps its row"
        )
        model.stop()
    }

    // -------------------------------------------------------------- Power

    @Test
    fun `the row after a start is what docker says, not what start meant`() =
        runTest(StandardTestDispatcher()) {
            val control = Scripted(
                listOf(Result.success(listOf(ContainerStatus("adguardhome", "Exited (1) 2 seconds ago"))))
            )
            val model = model(CoroutineScope(coroutineContext), control)
            model.power(server(), adguard, ServicePowerAction.START)
            runCurrent()

            val state = model.states.value.getValue(adguard)
            assertEquals(HealthLevel.CRITICAL, state.containers.single().health)
            assertEquals(listOf("start:adguard-home"), control.asked)
            assertTrue(!state.isBusy)
            model.stop()
        }

    /** A failed action keeps the row it had */
    @Test
    fun `a failed action keeps the last known row and says why`() = runTest(StandardTestDispatcher()) {
        val released = mutableListOf<String>()
        val control = Scripted(
            listOf(
                Result.success(listOf(ContainerStatus("adguardhome", "Up 2 days"))),
                Result.failure(RuntimeException("sudo: a password is required")),
            )
        )
        val model = model(CoroutineScope(coroutineContext), control, released)
        val deployment = server(services = setOf(adguard))
        model.refresh(deployment)
        runCurrent()
        model.power(deployment, adguard, ServicePowerAction.STOP)
        runCurrent()

        val state = model.states.value.getValue(adguard)
        assertEquals("Up 2 days", state.containers.single().status, "the row survives a failed action")
        assertEquals("sudo: a password is required", state.errorMessage)
        assertEquals(listOf("S-1"), released, "a failure drops the session reference")
        model.stop()
    }

    @Test
    fun `an empty answer is still an answer`() = runTest(StandardTestDispatcher()) {
        val control = Scripted(listOf(Result.success(emptyList())))
        val model = model(CoroutineScope(coroutineContext), control)
        model.refresh(server(services = setOf(adguard)))
        runCurrent()

        val state = model.states.value.getValue(adguard)
        assertTrue(state.containers.isEmpty())
        assertTrue(state.hasAnswered)
        assertNull(state.errorMessage)
        model.stop()
    }

    // ------------------------------------------------------------- Routing

    /** Both inputs decide, and both are asserted */
    @Test
    fun `the route needs an agent on the server AND a transport in the app`() =
        runTest(StandardTestDispatcher()) {
            val withTransport = ServiceControlViewModel(
                scope = CoroutineScope(coroutineContext),
                runners = { Unused },
                control = { _, _ -> Scripted(emptyList()) },
                agentTransportAvailable = true,
            )
            assertEquals(ServiceControlRoute.AGENT, withTransport.route(server().copy(usesAgent = true)))
            assertEquals(ServiceControlRoute.SSH, withTransport.route(server()))

            val withoutTransport = ServiceControlViewModel(
                scope = CoroutineScope(coroutineContext),
                runners = { Unused },
                control = { _, _ -> Scripted(emptyList()) },
                agentTransportAvailable = false,
            )
            assertEquals(ServiceControlRoute.SSH, withoutTransport.route(server().copy(usesAgent = true)))
            assertEquals(ServiceControlRoute.SSH, withoutTransport.route(server()))
        }

    /** The number the friendly level shows instead of the list */
    @Test
    fun `the summary counts every container that is not healthy`() {
        val healthy = ServiceState(
            containers = listOf(
                ContainerStatus("adguardhome", "Up 2 days"),
                ContainerStatus("caddy", "Up 3 hours (healthy)"),
            )
        )
        assertEquals(0, healthy.containersNeedingAttention)

        val broken = ServiceState(
            containers = listOf(
                ContainerStatus("adguardhome", "Up 2 days"),
                ContainerStatus("db", "Exited (1) 2 seconds ago"),
                ContainerStatus("worker", "Restarting (1) 5 seconds ago"),
            )
        )
        assertEquals(2, broken.containersNeedingAttention)

        assertEquals(0, ServiceState().containersNeedingAttention, "nothing read is nothing wrong")
    }
}
