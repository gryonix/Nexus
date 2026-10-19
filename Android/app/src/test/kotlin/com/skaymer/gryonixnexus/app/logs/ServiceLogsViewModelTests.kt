package com.skaymer.gryonixnexus.app.logs

import com.skaymer.gryonixnexus.agentcontrol.ContainerLogLine
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.ServiceControlRoute
import java.io.IOException
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

/** One service's log */
class ServiceLogsViewModelTests {
    private fun server(usesAgent: Boolean = true) = Deployment(
        id = "S-1",
        name = "middle",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
        services = setOf(ServiceID.NEXTCLOUD),
        usesAgent = usesAgent,
    )

    private fun service(id: ServiceID = ServiceID.NEXTCLOUD): ManagedService =
        ServiceRegistry.service(id)!!

    private fun model(
        scope: CoroutineScope,
        stream: (Deployment, String) -> Flow<ContainerLogLine> = { _, _ -> flowOf() },
        snapshot: suspend (Deployment, ManagedService) -> List<String> = { _, _ -> emptyList() },
        agentTransportAvailable: Boolean = true,
    ) = ServiceLogsViewModel(
        scope = scope,
        streams = stream,
        snapshots = snapshot,
        agentTransportAvailable = agentTransportAvailable,
    )

    // ------------------------------------------------------------- Routing

    @Test
    fun `an agent server follows, and a server without one reads a tail`() {
        assertEquals(
            ServiceControlRoute.AGENT,
            ServiceLogsRouting.route(
                usesAgent = true,
                agentTransportAvailable = true,
                agentServiceID = "nextcloud",
            ),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            ServiceLogsRouting.route(
                usesAgent = false,
                agentTransportAvailable = true,
                agentServiceID = "nextcloud",
            ),
        )
    }

    @Test
    fun `a service the agent has no id for stays on SSH even on an agent server`() {
        assertEquals(
            ServiceControlRoute.SSH,
            ServiceLogsRouting.route(
                usesAgent = true,
                agentTransportAvailable = true,
                agentServiceID = null,
            ),
        )
    }

    @Test
    fun `a transport that is not there falls back to the tail`() {
        assertEquals(
            ServiceControlRoute.SSH,
            ServiceLogsRouting.route(
                usesAgent = true,
                agentTransportAvailable = false,
                agentServiceID = "nextcloud",
            ),
        )
    }

    // ---------------------------------------------------------------- Reads

    @Test
    fun `the agent route follows live and tags every line`() = runTest(StandardTestDispatcher()) {
        val logs = model(
            this,
            stream = { _, _ ->
                flowOf(
                    ContainerLogLine("nextcloud-app-1", "ready", "stdout"),
                    ContainerLogLine("nextcloud-db-1", "listening", "stderr"),
                )
            },
        )
        logs.start(server(), service())
        runCurrent()

        val state = logs.state.value
        assertEquals(ServiceLogsKind.LIVE, state.kind)
        assertEquals(listOf("nextcloud-app-1", "nextcloud-db-1"), state.containers)
        assertEquals(listOf("ready", "listening"), state.lines.map { it.text })
        assertEquals("stderr", state.lines[1].stream)
    }

    @Test
    fun `the SSH route is a snapshot with no container tags`() = runTest(StandardTestDispatcher()) {
        val logs = model(this, snapshot = { _, _ -> listOf("one", "two") })
        logs.start(server(usesAgent = false), service())
        runCurrent()

        val state = logs.state.value
        assertEquals(ServiceLogsKind.SNAPSHOT, state.kind)
        assertFalse(state.isLive)
        assertEquals(listOf("one", "two"), state.lines.map { it.text })
        assertTrue(state.containers.isEmpty())
        assertEquals(ServiceLogsStatus.ENDED, state.status)
    }

    @Test
    fun `only a finished, unfailed, empty read says the service printed nothing`() =
        runTest(StandardTestDispatcher()) {
            val quiet = model(this, snapshot = { _, _ -> emptyList() })
            quiet.start(server(usesAgent = false), service())
            runCurrent()
            assertTrue(quiet.state.value.saysThereIsNoOutput)

            val broken = model(this, snapshot = { _, _ -> throw IOException("channel closed") })
            broken.start(server(usesAgent = false), service())
            runCurrent()
            assertFalse(broken.state.value.saysThereIsNoOutput)
            assertEquals(ServiceLogsStatus.FAILED, broken.state.value.status)
            assertEquals("channel closed", broken.state.value.errorMessage)
        }

    @Test
    fun `a read still running says nothing about output either`() = runTest(StandardTestDispatcher()) {
        val logs = model(this, snapshot = { _, _ -> listOf("late") })
        logs.start(server(usesAgent = false), service())
        // Not run yet: connecting, empty, and silent about the service.
        assertEquals(ServiceLogsStatus.CONNECTING, logs.state.value.status)
        assertFalse(logs.state.value.saysThereIsNoOutput)
    }

    @Test
    fun `asking again replaces the tail rather than printing it twice`() =
        runTest(StandardTestDispatcher()) {
            var reads = 0
            val logs = model(
                this,
                snapshot = { _, _ ->
                    reads += 1
                    listOf("line A", "line B")
                },
            )
            logs.start(server(usesAgent = false), service())
            runCurrent()
            logs.reload()
            runCurrent()

            assertEquals(2, reads)
            assertEquals(listOf("line A", "line B"), logs.state.value.lines.map { it.text })
        }

    @Test
    fun `a live follow has nothing to ask again`() = runTest(StandardTestDispatcher()) {
        var snapshots = 0
        val logs = model(
            this,
            stream = { _, _ -> flowOf(ContainerLogLine("nextcloud-app-1", "ready", "stdout")) },
            snapshot = { _, _ -> snapshots += 1; emptyList() },
        )
        logs.start(server(), service())
        runCurrent()
        logs.reload()
        runCurrent()

        assertEquals(0, snapshots)
        assertEquals(listOf("ready"), logs.state.value.lines.map { it.text })
    }

    // ------------------------------------------------------------ The buffer

    @Test
    fun `a chatty service cannot grow the buffer without end`() = runTest(StandardTestDispatcher()) {
        val chatty = (1..ServiceLogsViewModel.BUFFER_LIMIT + 50).map {
            ContainerLogLine("app-1", "line $it", "stdout")
        }
        val logs = model(this, stream = { _, _ -> flowOf(*chatty.toTypedArray()) })
        logs.start(server(), service())
        runCurrent()

        val lines = logs.state.value.lines
        assertEquals(ServiceLogsViewModel.BUFFER_LIMIT, lines.size)
        assertEquals("line ${ServiceLogsViewModel.BUFFER_LIMIT + 50}", lines.last().text)
    }

    // ------------------------------------------------------------ The screen

    @Test
    fun `filtering shows one container, and copying takes what is on screen`() =
        runTest(StandardTestDispatcher()) {
            val logs = model(
                this,
                stream = { _, _ ->
                    flowOf(
                        ContainerLogLine("nextcloud-app-1", "ready", "stdout"),
                        ContainerLogLine("nextcloud-db-1", "listening", "stdout"),
                    )
                },
            )
            logs.start(server(), service())
            runCurrent()

            // Unfiltered, several sources: every line says which wrote it.
            assertEquals("[app] ready\n[db] listening", logs.state.value.plainText())

            logs.filter("nextcloud-db-1")
            assertEquals(listOf("listening"), logs.state.value.visible.map { it.text })
            assertEquals("listening", logs.state.value.plainText())
        }

    @Test
    fun `closing forgets the lines`() = runTest(StandardTestDispatcher()) {
        val logs = model(this, snapshot = { _, _ -> listOf("one") })
        logs.start(server(usesAgent = false), service())
        runCurrent()
        assertEquals(1, logs.state.value.lines.size)

        logs.close()
        assertTrue(logs.state.value.lines.isEmpty())
        assertNull(logs.state.value.errorMessage)
        assertEquals(ServiceLogsStatus.CONNECTING, logs.state.value.status)
    }
}
