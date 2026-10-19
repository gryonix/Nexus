package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.catalog.ComposeFile
import com.skaymer.gryonixnexus.catalog.FirewallPort
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.PrivilegedCommand
import com.skaymer.gryonixnexus.catalog.ServiceActions
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.StatusProbe
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.catalog.WebIngress
import com.skaymer.gryonixnexus.servercontrol.RestoreRouting
import com.skaymer.gryonixnexus.servercontrol.ServiceControlRoute
import gryonixnexusd.v1.Container
import gryonixnexusd.v1.RestoreEvent
import gryonixnexusd.v1.RunRestoreRequest
import gryonixnexusd.v1.Service
import gryonixnexusd.v1.ServiceOperationPhase
import gryonixnexusd.v1.ServiceStatusResponse
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

private class UnknownFutureService : ManagedService {
    override val id = ServiceID("some-future-service")
    override val displayName = "Future Service"
    override val systemImage = "questionmark.circle"
    override val category = ServiceCategory.FILES
    override val runtime = ServiceRuntime.Docker(composeProject = "future-service")

    override fun composeFile(context: ServiceContext): ComposeFile? = null
    override fun setupSteps(context: ServiceContext): List<String> = emptyList()
    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()
    override fun webIngress(context: ServiceContext): WebIngress? = null
    override fun dnsHostnames(context: ServiceContext): List<String> = emptyList()

    override fun actions(context: ServiceContext) = ServiceActions(
        statusProbe = StatusProbe.ComposeProject(
            project = "future-service",
            list = PrivilegedCommand("/usr/bin/docker", "compose -p future-service ps"),
        ),
    )

    override fun updateSpec(context: ServiceContext) = UpdateSpec(images = listOf("example/future-service:1"))
}

/** The Kotlin twin of `AgentRestoreOperationsTests` */
class AgentRestoreOperationsTest {
    private fun service(id: ServiceID): ManagedService = checkNotNull(ServiceRegistry.service(id))

    private fun event(
        phase: ServiceOperationPhase,
        text: String = "",
        installed: Boolean? = null,
        containers: List<Container> = emptyList(),
    ) = RestoreEvent(
        phase = phase,
        text = text,
        status = installed?.let {
            ServiceStatusResponse(
                installed = it,
                service = containers.takeIf { c -> c.isNotEmpty() }?.let { c -> Service(containers = c) },
            )
        },
    )

    private fun restore(transport: FakeAgentTransport) = AgentRestoreOperations(AgentClient(transport))

    // ------------------------------------------------------------- Routing

    @Test
    fun `restore routing has no per-service exception unlike backup routing`() {
        assertEquals(
            ServiceControlRoute.AGENT,
            RestoreRouting.route(usesAgent = true, agentTransportAvailable = true),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            RestoreRouting.route(usesAgent = true, agentTransportAvailable = false),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            RestoreRouting.route(usesAgent = false, agentTransportAvailable = true),
        )
    }

    // ------------------------------------------------------------- Restore

    @Test
    fun `a successful restore sends the archive path and passphrase and returns the log`() = runTest {
        val transport = FakeAgentTransport()
        transport.stream(
            "Restore/RunRestore",
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_STARTED),
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS, text = "restoring nextcloud data"),
            event(
                ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED,
                installed = true,
                containers = listOf(Container(name = "nextcloud-app", state = "running")),
            ),
        )

        val chunks = mutableListOf<String>()
        val log = restore(transport).restore(
            service(ServiceID.NEXTCLOUD),
            archivePath = "/opt/backups/nextcloud/2026.tar.gz",
            passphrase = "hunter2",
        ) { chunks += it }

        assertEquals(listOf("/gryonixnexusd.v1.Restore/RunRestore"), transport.paths)
        val sent = RunRestoreRequest.ADAPTER.decode(transport.calls.first().second)
        assertEquals("nextcloud", sent.service_id)
        assertEquals("/opt/backups/nextcloud/2026.tar.gz", sent.archive_path)
        assertEquals("hunter2", sent.passphrase)
        assertEquals(listOf("restoring nextcloud data\n"), chunks)
        assertTrue(log.contains("restoring nextcloud data"), log)
    }

    @Test
    fun `a null passphrase is sent as empty never omitted`() = runTest {
        val transport = FakeAgentTransport()
        transport.stream(
            "Restore/RunRestore",
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED, installed = true),
        )

        restore(transport).restore(
            service(ServiceID.NEXTCLOUD),
            archivePath = "/opt/backups/nextcloud/plain.tar.gz",
            passphrase = null,
        ) { }

        assertEquals("", RunRestoreRequest.ADAPTER.decode(transport.calls.first().second).passphrase)
    }

    @Test
    fun `a failed restore throws and carries the re-read status`() = runTest {
        val transport = FakeAgentTransport()
        transport.streamThenFail(
            "Restore/RunRestore",
            AgentError.Rpc("internal", "the nextcloud database could not be restored"),
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS, text = "restoring nextcloud data"),
            event(
                ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED,
                installed = true,
                containers = listOf(Container(name = "nextcloud-app", state = "exited")),
            ),
        )

        val error = runCatching {
            restore(transport).restore(
                service(ServiceID.NEXTCLOUD),
                archivePath = "/opt/backups/nextcloud/x.tar.gz",
                passphrase = null,
            ) { }
        }.exceptionOrNull()

        assertTrue(error is AgentControlError.OperationFailed, "got $error")
        assertEquals(
            AgentError.Rpc("internal", "the nextcloud database could not be restored"),
            error.underlying,
        )
        assertEquals(listOf("nextcloud-app"), error.status.map { it.name })
    }

    @Test
    fun `a refusal before anything ran keeps its own connect code`() = runTest {
        val refusal = AgentError.Rpc("failed_precondition", "this server has no restore wrapper")
        val transport = FakeAgentTransport()
        transport.fail("Restore/RunRestore", refusal)

        val error = runCatching {
            restore(transport).restore(
                service(ServiceID.IMMICH),
                archivePath = "/opt/backups/immich/x.tar.gz",
                passphrase = null,
            ) { }
        }.exceptionOrNull()

        assertEquals(refusal, error)
    }

    @Test
    fun `an unsupported service falls back without ever reaching the transport`() = runTest {
        val transport = FakeAgentTransport()

        val error = runCatching {
            restore(transport).restore(
                UnknownFutureService(),
                archivePath = "/opt/backups/future-service/x.tar.gz",
                passphrase = null,
            ) { }
        }.exceptionOrNull()

        assertTrue(error is AgentControlError.UnsupportedService, "got $error")
        assertTrue(transport.paths.isEmpty(), "an unmapped service must be refused before any call")
    }
}
