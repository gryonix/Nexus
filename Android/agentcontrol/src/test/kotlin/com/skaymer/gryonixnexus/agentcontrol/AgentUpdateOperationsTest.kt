package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceUpdateStatus
import com.skaymer.gryonixnexus.servercontrol.AutoUpdateSettings
import com.skaymer.gryonixnexus.servercontrol.CommandCatalog
import com.skaymer.gryonixnexus.servercontrol.ServerControlError
import com.skaymer.gryonixnexus.servercontrol.ServiceControlRoute
import com.skaymer.gryonixnexus.servercontrol.ServiceUpdateRunRecord
import com.skaymer.gryonixnexus.servercontrol.ServiceUpdateRouting
import gryonixnexusd.v1.RunUpdateRequest
import gryonixnexusd.v1.ServiceOperationPhase
import gryonixnexusd.v1.SetUpdateScheduleRequest
import gryonixnexusd.v1.UpdateAvailability
import gryonixnexusd.v1.UpdateCheckResult
import gryonixnexusd.v1.UpdateEvent
import gryonixnexusd.v1.UpdateOutcome
import gryonixnexusd.v1.UpdatePolicy
import gryonixnexusd.v1.UpdateRunRecord
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of `AgentUpdateOperationsTests` */
class AgentUpdateOperationsTest {
    private fun event(
        phase: ServiceOperationPhase,
        text: String = "",
        outcome: UpdateOutcome = UpdateOutcome.UPDATE_OUTCOME_UNSPECIFIED,
        reason: String = "",
    ) = UpdateEvent(phase = phase, text = text, outcome = outcome, reason = reason)

    private fun updates(transport: FakeAgentTransport) = AgentUpdateOperations(AgentClient(transport))

    // ------------------------------------------------------------- Routing

    @Test
    fun `updates follow the same route as control actions`() {
        assertEquals(
            ServiceControlRoute.AGENT,
            ServiceUpdateRouting.route(usesAgent = true, agentTransportAvailable = true),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            ServiceUpdateRouting.route(usesAgent = true, agentTransportAvailable = false),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            ServiceUpdateRouting.route(usesAgent = false, agentTransportAvailable = true),
        )
    }

    // --------------------------------------------------------------- Check

    @Test
    fun `check maps availability and keeps unrecognised ids`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Update/CheckUpdates",
            UpdateCheckResult(
                services = listOf(
                    gryonixnexusd.v1.ServiceUpdateStatus(
                        service_id = "nextcloud",
                        availability = UpdateAvailability.UPDATE_AVAILABILITY_CURRENT,
                    ),
                    gryonixnexusd.v1.ServiceUpdateStatus(
                        service_id = "vaultwarden",
                        availability = UpdateAvailability.UPDATE_AVAILABILITY_AVAILABLE,
                        moved_images = listOf("vaultwarden/server:1.34.0"),
                    ),
                    gryonixnexusd.v1.ServiceUpdateStatus(
                        service_id = "immich",
                        availability = UpdateAvailability.UPDATE_AVAILABILITY_UNKNOWN,
                        reason = "registry_unreachable",
                    ),
                    gryonixnexusd.v1.ServiceUpdateStatus(
                        service_id = "some-future-service",
                        availability = UpdateAvailability.UPDATE_AVAILABILITY_CURRENT,
                    ),
                    gryonixnexusd.v1.ServiceUpdateStatus(
                        service_id = "vpn",
                        availability = UpdateAvailability.UPDATE_AVAILABILITY_CURRENT,
                    ),
                ),
            ),
        )

        val reports = updates(transport).check()

        assertEquals(listOf("/gryonixnexusd.v1.Update/CheckUpdates"), transport.paths)
        assertEquals(5, reports.size)
        assertEquals(ServiceID.NEXTCLOUD, reports[0].service)
        assertEquals(ServiceUpdateStatus.Current, reports[0].status)
        assertEquals(ServiceID.VAULTWARDEN, reports[1].service)
        assertEquals(ServiceUpdateStatus.Available(listOf("vaultwarden/server:1.34.0")), reports[1].status)
        assertEquals(ServiceID.IMMICH, reports[2].service)
        assertEquals(ServiceUpdateStatus.Unknown, reports[2].status)
        assertEquals(ServiceID("some-future-service"), reports[3].service)
        assertEquals(ServiceID.VPN_PANEL, reports[4].service)
    }

    // ----------------------------------------------------------------- Run

    @Test
    fun `a successful run returns the updated outcome with no trailer at all`() = runTest {
        val transport = FakeAgentTransport()
        transport.stream(
            "Update/RunUpdate",
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_STARTED),
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS, text = "pulling nextcloud"),
            event(
                ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED,
                outcome = UpdateOutcome.UPDATE_OUTCOME_UPDATED,
            ),
        )

        val progress = mutableListOf<String>()
        val record = updates(transport).run(ServiceID.NEXTCLOUD) { progress += it }

        assertEquals(listOf("/gryonixnexusd.v1.Update/RunUpdate"), transport.paths)
        assertEquals("nextcloud", RunUpdateRequest.ADAPTER.decode(transport.calls.first().second).service_id)
        assertEquals(ServiceID.NEXTCLOUD, record.service)
        assertEquals(ServiceUpdateRunRecord.Outcome.Updated, record.outcome)
        assertEquals(listOf("pulling nextcloud\n"), progress)
    }

    @Test
    fun `a rolled back run is a result not a throw`() = runTest {
        val transport = FakeAgentTransport()
        transport.streamThenFail(
            "Update/RunUpdate",
            AgentError.Rpc("internal", "a container is restarting"),
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS, text = "waiting for health"),
            event(
                ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED,
                outcome = UpdateOutcome.UPDATE_OUTCOME_ROLLED_BACK,
                reason = "a container is restarting",
            ),
        )

        val record = updates(transport).run(ServiceID.NEXTCLOUD) { }

        assertEquals(ServiceUpdateRunRecord.Outcome.RolledBack("a container is restarting"), record.outcome)
    }

    @Test
    fun `a failed run is a result not a throw`() = runTest {
        val transport = FakeAgentTransport()
        transport.streamThenFail(
            "Update/RunUpdate",
            AgentError.Rpc("internal", "the backup failed"),
            event(
                ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED,
                outcome = UpdateOutcome.UPDATE_OUTCOME_FAILED,
                reason = "the backup failed",
            ),
        )

        val record = updates(transport).run(ServiceID.VAULTWARDEN) { }

        assertEquals(ServiceUpdateRunRecord.Outcome.Failed("the backup failed"), record.outcome)
    }

    @Test
    fun `a refusal with no completed event at all still throws`() = runTest {
        val transport = FakeAgentTransport()
        transport.refuse(
            "Update/RunUpdate",
            code = "failed_precondition",
            text = "mailcow ships its own updater, so this wrapper does not swap its images",
        )

        val error = runCatching { updates(transport).run(ServiceID.MAILCOW) { } }.exceptionOrNull()

        assertTrue(error is ServerControlError.CommandFailed, "got $error")
        assertEquals(
            "mailcow ships its own updater, so this wrapper does not swap its images",
            error.stderr,
        )
    }

    // --------------------------------------------------- Schedule / status

    @Test
    fun `load schedule and load status both read the one policy call`() = runTest {
        val policy = UpdatePolicy(
            schedule = "every:1d@04:30",
            services = listOf("nextcloud", "vaultwarden"),
            last_run = listOf(
                UpdateRunRecord(service_id = "nextcloud", outcome = UpdateOutcome.UPDATE_OUTCOME_UPDATED),
            ),
            last_run_at = 1_754_600_000_000,
        )
        val transport = FakeAgentTransport()
        transport.reply("Update/GetUpdatePolicy", policy)
        transport.reply("Update/GetUpdatePolicy", policy)

        val settings = updates(transport).loadSchedule()
        assertEquals(CommandCatalog.Backups.Schedule.Days(count = 1, hour = 4, minute = 30), settings.schedule)
        assertEquals(setOf("nextcloud", "vaultwarden"), settings.services)

        val log = updates(transport).loadStatus()
        assertEquals(ServiceID.NEXTCLOUD, log.records.first().service)
        assertEquals(ServiceUpdateRunRecord.Outcome.Updated, log.records.first().outcome)
        assertNotNull(log.lastRun)

        assertEquals(
            listOf("/gryonixnexusd.v1.Update/GetUpdatePolicy", "/gryonixnexusd.v1.Update/GetUpdatePolicy"),
            transport.paths,
        )
    }

    @Test
    fun `save sends the grammar and the checked services in a stable order`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Update/SetUpdateSchedule", UpdatePolicy())

        updates(transport).save(
            AutoUpdateSettings(
                schedule = CommandCatalog.Backups.Schedule.Hours(count = 6, minute = 0),
                services = setOf("vaultwarden", "nextcloud"),
            ),
        )

        assertEquals(listOf("/gryonixnexusd.v1.Update/SetUpdateSchedule"), transport.paths)
        val sent = SetUpdateScheduleRequest.ADAPTER.decode(transport.calls.first().second)
        assertEquals("every:6h@00:00", sent.schedule)
        assertEquals(listOf("nextcloud", "vaultwarden"), sent.services)
    }
}
