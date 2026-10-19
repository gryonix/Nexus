package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.ServiceID
import gryonixnexusd.v1.Container
import gryonixnexusd.v1.InstallServiceEvent
import gryonixnexusd.v1.InstallServiceRequest
import gryonixnexusd.v1.ProvisionHostRequest
import gryonixnexusd.v1.ProvisionHostResponse
import gryonixnexusd.v1.Service
import gryonixnexusd.v1.ServiceOperationPhase
import gryonixnexusd.v1.WatchInstallRequest
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of `AgentInstallOperationsTests` */
class AgentInstallOperationsTest {
    private fun event(
        phase: ServiceOperationPhase,
        text: String = "",
        containers: List<Container>? = null,
        jobID: String = "",
    ) = InstallServiceEvent(
        phase = phase,
        text = text,
        service = containers?.let { Service(containers = it) },
        job_id = jobID,
    )

    private fun install(transport: FakeAgentTransport) = AgentInstallOperations(AgentClient(transport))

    // ------------------------------------------------------------- Install

    @Test
    fun `a successful install sends the whole context and returns the streamed log`() = runTest {
        val transport = FakeAgentTransport()
        transport.stream(
            "Install/InstallService",
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_STARTED),
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS, text = "waiting for AdGuard Home to answer"),
            event(
                ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED,
                containers = listOf(Container(name = "adguardhome", state = "running")),
            ),
        )

        val chunks = mutableListOf<String>()
        val log = install(transport).install(
            ServiceID.ADGUARD_HOME,
            AgentInstallContext(
                domain = "example.com",
                additionalDomains = listOf("example.net"),
                localOnly = false,
                adminUsername = "owner",
                language = AppLanguage.RU,
                settings = mapOf("adguard_path" to "/opt/adguardhome"),
            ),
            onChunk = { chunks += it },
        )

        assertEquals(listOf("/gryonixnexusd.v1.Install/InstallService"), transport.paths)
        val sent = InstallServiceRequest.ADAPTER.decode(transport.calls.first().second)
        assertEquals("adguard-home", sent.service_id)
        assertEquals("example.com", sent.domain)
        assertEquals(listOf("example.net"), sent.additional_domains)
        assertEquals(false, sent.local_only)
        assertEquals("owner", sent.admin_username)
        assertEquals("ru", sent.language)
        assertEquals(mapOf("adguard_path" to "/opt/adguardhome"), sent.settings)
        assertEquals(listOf("waiting for AdGuard Home to answer\n"), chunks)
        assertTrue(log.contains("waiting for AdGuard Home to answer"), log)
    }

    @Test
    fun `local only and defaults round trip faithfully`() = runTest {
        val transport = FakeAgentTransport()
        transport.stream(
            "Install/InstallService",
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED, containers = emptyList()),
        )

        install(transport).install(
            ServiceID.ADGUARD_HOME,
            AgentInstallContext(domain = "srv.local", localOnly = true),
            onChunk = { },
        )

        val sent = InstallServiceRequest.ADAPTER.decode(transport.calls.first().second)
        assertEquals(true, sent.local_only)
        assertEquals(emptyList(), sent.additional_domains)
        assertEquals("", sent.admin_username)
        assertEquals("en", sent.language)
        assertEquals(emptyMap(), sent.settings)
    }

    @Test
    fun `the job id is announced once from the first event that carries it`() = runTest {
        val transport = FakeAgentTransport()
        transport.stream(
            "Install/InstallService",
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_STARTED),
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS, text = "one", jobID = "job-7"),
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS, text = "two", jobID = "job-7"),
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED, containers = emptyList(), jobID = "job-7"),
        )

        val announced = mutableListOf<String>()
        install(transport).install(
            ServiceID.ADGUARD_HOME,
            AgentInstallContext(domain = "example.com"),
            onJobID = { announced += it },
            onChunk = { },
        )

        assertEquals(listOf("job-7"), announced)
    }

    // ------------------------------------------- The two-channel error rule

    @Test
    fun `a failed install throws and carries the re-read status`() = runTest {
        val transport = FakeAgentTransport()
        transport.streamThenFail(
            "Install/InstallService",
            AgentError.Rpc("internal", "docker pull failed: no space left on device"),
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS, text = "pulling adguard/adguardhome"),
            event(
                ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED,
                containers = listOf(Container(name = "adguardhome", state = "exited")),
            ),
        )

        val error = runCatching {
            install(transport).install(
                ServiceID.ADGUARD_HOME, AgentInstallContext(domain = "example.com"), onChunk = { },
            )
        }.exceptionOrNull()

        assertTrue(error is AgentControlError.OperationFailed, "got $error")
        assertEquals(
            AgentError.Rpc("internal", "docker pull failed: no space left on device"),
            error.underlying,
        )
        assertEquals(listOf("adguardhome"), error.status.map { it.name })
        assertEquals(listOf("Exited"), error.status.map { it.status })
    }

    @Test
    fun `the server's own words survive as the error message`() = runTest {
        val transport = FakeAgentTransport()
        transport.streamThenFail(
            "Install/InstallService",
            AgentError.Rpc("internal", "caddy reload failed: syntax error"),
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED, containers = emptyList()),
        )

        val error = runCatching {
            install(transport).install(
                ServiceID.ADGUARD_HOME, AgentInstallContext(domain = "example.com"), onChunk = { },
            )
        }.exceptionOrNull()

        assertTrue(
            error?.message.orEmpty().contains("caddy reload failed: syntax error"),
            "${error?.message}",
        )
    }

    /**
     * No COMPLETED at all — the id was real but this build's executor does not
     * implement it yet, per the RPC's own doc ("answers failed_precondition, not
     * not_found"). Nothing ran, so there is no status to carry; the original
     * error is rethrown untouched.
     */
    @Test
    fun `a refusal before anything ran keeps its own connect code`() = runTest {
        val refusal = AgentError.Rpc("failed_precondition", "this agent build cannot install adguard-home yet")
        val transport = FakeAgentTransport()
        transport.fail("Install/InstallService", refusal)

        val error = runCatching {
            install(transport).install(
                ServiceID.ADGUARD_HOME, AgentInstallContext(domain = "example.com"), onChunk = { },
            )
        }.exceptionOrNull()

        assertEquals(refusal, error)
    }

    /**
     * An id from a newer app than this agent: every service in today's catalog
     * is mapped, so the unmapped case is exactly the one that matters at runtime
     * — a client that knows a service this agent has never heard of must fall
     * back to SSH rather than call a route that does not exist.
     */
    @Test
    fun `an unsupported service falls back without ever reaching the transport`() = runTest {
        val transport = FakeAgentTransport()
        val chunks = mutableListOf<String>()

        val error = runCatching {
            install(transport).install(
                ServiceID("some-future-service"),
                AgentInstallContext(domain = "example.com"),
                onChunk = { chunks += it },
            )
        }.exceptionOrNull()

        assertTrue(error is AgentControlError.UnsupportedService, "got $error")
        assertTrue(transport.paths.isEmpty())
        assertTrue(chunks.isEmpty(), "no progress event should ever be produced for a refused call")
    }

    // --------------------------------------------------------------- Watch

    @Test
    fun `a resumed run reads back the same way a fresh one does`() = runTest {
        val transport = FakeAgentTransport()
        transport.stream(
            "Install/WatchInstall",
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS, text = "still pulling"),
            event(
                ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED,
                containers = listOf(Container(name = "adguardhome", state = "running")),
            ),
        )

        val chunks = mutableListOf<String>()
        val log = install(transport).watch("job-7", from = 41, onChunk = { chunks += it })

        assertEquals(listOf("/gryonixnexusd.v1.Install/WatchInstall"), transport.paths)
        val sent = WatchInstallRequest.ADAPTER.decode(transport.calls.first().second)
        assertEquals("job-7", sent.job_id)
        assertEquals(41, sent.from_sequence)
        assertEquals(listOf("still pulling\n"), chunks)
        assertTrue(log.contains("still pulling"), log)
    }

    @Test
    fun `a resumed run that fails midway carries the re-read status too`() = runTest {
        val transport = FakeAgentTransport()
        transport.streamThenFail(
            "Install/WatchInstall",
            AgentError.Rpc("internal", "the agent died mid-run"),
            event(
                ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED,
                containers = listOf(Container(name = "adguardhome", state = "exited")),
            ),
        )

        val error = runCatching { install(transport).watch("job-7", onChunk = { }) }.exceptionOrNull()

        assertTrue(error is AgentControlError.OperationFailed, "got $error")
        assertEquals(listOf("adguardhome"), error.status.map { it.name })
    }

    // -------------------------------------------------------- provisionHost

    @Test
    fun `provisioning answers with what it wrote and what it did besides`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Install/ProvisionHost",
            ProvisionHostResponse(
                written = listOf("/opt/gryonixnexus-uninstall.sh", "/etc/sudoers.d/gryonixnexus"),
                control_user = "gryonixnexus",
                notes = listOf("refused to rewrite an nftables ruleset this agent did not write"),
            ),
        )

        val outcome = install(transport).provisionHost(
            AgentInstallContext(domain = "example.com", adminUsername = "owner"),
        )

        assertEquals(listOf("/gryonixnexusd.v1.Install/ProvisionHost"), transport.paths)
        val sent = ProvisionHostRequest.ADAPTER.decode(transport.calls.first().second)
        assertEquals("example.com", sent.domain)
        assertEquals("owner", sent.admin_username)
        assertEquals(listOf("/opt/gryonixnexus-uninstall.sh", "/etc/sudoers.d/gryonixnexus"), outcome.written)
        assertEquals("gryonixnexus", outcome.controlUser)
        assertEquals(
            listOf("refused to rewrite an nftables ruleset this agent did not write"),
            outcome.notes,
        )
    }

    @Test
    fun `a host with no control user answers with an empty one rather than failing`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Install/ProvisionHost", ProvisionHostResponse(written = listOf("/opt/x.sh")))

        val outcome = install(transport).provisionHost(AgentInstallContext(domain = "example.com"))

        assertEquals("", outcome.controlUser)
        assertTrue(outcome.notes.isEmpty())
    }

    // ------------------------------------------------------------- The gate

    @Test
    fun `the short verbs are serialized by a provided gate`() = runBlocking {
        val transport = GatedTransport(ProvisionHostResponse())
        val ops = AgentInstallOperations(AgentClient(transport), gate = AgentChannelGate(limit = 1))

        (0 until 6)
            .map {
                launch(Dispatchers.Default) {
                    ops.provisionHost(AgentInstallContext(domain = "example.com"))
                }
            }
            .forEach { it.join() }

        assertEquals(1, transport.highest, "more than one call ran at once under a limit-1 gate")
    }

    @Test
    fun `with no gate the short verbs genuinely overlap`() = runBlocking {
        val transport = GatedTransport(ProvisionHostResponse())
        val ops = AgentInstallOperations(AgentClient(transport))

        (0 until 6)
            .map {
                launch(Dispatchers.Default) {
                    ops.provisionHost(AgentInstallContext(domain = "example.com"))
                }
            }
            .forEach { it.join() }

        assertTrue(
            transport.highest > 1,
            "calls did not overlap even without a gate — the harness is not sensitive",
        )
    }
}
