package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.ServiceUpdateStatus
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.servercontrol.AutoUpdateSettings
import com.skaymer.gryonixnexus.servercontrol.CommandCatalog
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.ServiceUpdateManaging
import com.skaymer.gryonixnexus.servercontrol.ServiceUpdateReport
import com.skaymer.gryonixnexus.servercontrol.ServiceUpdateRunLog
import com.skaymer.gryonixnexus.servercontrol.ServiceUpdateRunRecord
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

/** Updates for one server */
class UpdatesViewModelTests {
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

    /** An update wrapper that answers from a script */
    private class Scripted(
        val check: () -> List<ServiceUpdateReport> = { emptyList() },
        val schedule: () -> AutoUpdateSettings = { AutoUpdateSettings() },
        val status: () -> ServiceUpdateRunLog = { ServiceUpdateRunLog(null, emptyList()) },
        val run: (ServiceID, (String) -> Unit) -> ServiceUpdateRunRecord =
            { id, _ -> ServiceUpdateRunRecord(id, ServiceUpdateRunRecord.Outcome.Updated) },
        val save: (AutoUpdateSettings) -> Unit = {},
    ) : ServiceUpdateManaging {
        val asked = mutableListOf<String>()
        var saved: AutoUpdateSettings? = null

        override suspend fun check(): List<ServiceUpdateReport> {
            asked += "check"
            return check.invoke()
        }

        override suspend fun run(
            service: ServiceID,
            onChunk: (String) -> Unit,
        ): ServiceUpdateRunRecord {
            asked += "run:${service.rawValue}"
            return run.invoke(service, onChunk)
        }

        override suspend fun loadSchedule(): AutoUpdateSettings {
            asked += "schedule"
            return schedule.invoke()
        }

        override suspend fun loadStatus(): ServiceUpdateRunLog {
            asked += "status"
            return status.invoke()
        }

        override suspend fun save(settings: AutoUpdateSettings) {
            asked += "save"
            save.invoke(settings)
            saved = settings
        }
    }

    private fun model(
        scope: CoroutineScope,
        updates: Scripted,
        released: MutableList<String> = mutableListOf(),
    ) = UpdatesViewModel(
        scope = scope,
        updates = { updates },
        release = { released += it.id },
    )

    // -------------------------------------------------------------- Checking

    @Test
    fun `a service the check skipped is answered from the catalog`() = runTest(StandardTestDispatcher()) {
        val updates = Scripted(check = {
            listOf(ServiceUpdateReport(adguard, ServiceUpdateStatus.Available(listOf("adguard/adguardhome"))))
        })
        val model = model(CoroutineScope(coroutineContext), updates)
        model.check(server())
        runCurrent()

        val reports = model.state.value.reports
        assertEquals(ServiceUpdateStatus.Available(listOf("adguard/adguardhome")), reports[adguard])
        assertEquals(ServiceUpdateStatus.Unknown, reports[forgejo])
    }

    @Test
    fun `a service with nothing to poll is not drawn as a failed check`() {
        val deployment = server()
        val built = ServiceRegistry.all.first {
            it.updateSpec(deployment.serviceContext).flavour == UpdateSpec.Flavour.BUILT_ON_SERVER
        }
        val own = ServiceRegistry.all.first {
            it.updateSpec(deployment.serviceContext).flavour == UpdateSpec.Flavour.OWN_UPDATER
        }

        assertEquals(
            ServiceUpdateStatus.RebuiltBySetup,
            UpdatesViewModel.statusForUnreported(built, deployment.serviceContext),
        )
        assertEquals(
            ServiceUpdateStatus.SelfManaged,
            UpdatesViewModel.statusForUnreported(own, deployment.serviceContext),
        )
    }

    /** A failed check clears the board */
    @Test
    fun `a failed check clears what the last one said`() = runTest(StandardTestDispatcher()) {
        var fail = false
        val updates = Scripted(check = {
            if (fail) throw RuntimeException("connection closed")
            listOf(ServiceUpdateReport(adguard, ServiceUpdateStatus.Current))
        })
        val released = mutableListOf<String>()
        val model = model(CoroutineScope(coroutineContext), updates, released)
        model.check(server(services = setOf(adguard)))
        runCurrent()
        assertEquals(ServiceUpdateStatus.Current, model.state.value.reports[adguard])

        fail = true
        model.check(server(services = setOf(adguard)))
        runCurrent()

        assertTrue(model.state.value.reports.isEmpty(), "stale answers do not survive a failure")
        assertEquals("connection closed", model.state.value.errorMessage)
        assertEquals(listOf("S-1"), released, "a dead link is dropped, not reused")
    }

    // -------------------------------------------------------------- Loading

    @Test
    fun `an unreadable run log stays silent while an unreadable schedule does not`() =
        runTest(StandardTestDispatcher()) {
            val quiet = Scripted(
                schedule = { AutoUpdateSettings(CommandCatalog.Backups.Schedule.Days(1, 4, 0), setOf("adguard-home")) },
                status = { throw RuntimeException("no such file") },
            )
            val model = model(CoroutineScope(coroutineContext), quiet)
            model.load(server())
            runCurrent()

            assertNull(model.state.value.errorMessage, "a missing status file is not news")
            assertTrue(model.state.value.runLog.isEmpty)
            assertTrue(model.state.value.schedule.isOn)

            val loud = Scripted(schedule = { throw RuntimeException("permission denied") })
            val second = model(CoroutineScope(coroutineContext), loud)
            second.load(server())
            runCurrent()

            assertEquals("permission denied", second.state.value.errorMessage)
        }

    @Test
    fun `the schedule is not claimed until the server answers`() = runTest(StandardTestDispatcher()) {
        val updates = Scripted(
            schedule = { AutoUpdateSettings(CommandCatalog.Backups.Schedule.Days(1, 4, 0), setOf("adguard-home")) }
        )
        val model = model(CoroutineScope(coroutineContext), updates)
        assertTrue(!model.state.value.hasLoadedSchedule, "nothing has been read yet")

        model.load(server())
        runCurrent()

        assertTrue(model.state.value.hasLoadedSchedule)
        assertTrue(model.state.value.schedule.isOn)
    }

    // --------------------------------------------------------------- Saving

    @Test
    fun `a refused schedule is not shown as saved`() = runTest(StandardTestDispatcher()) {
        val updates = Scripted(save = { throw RuntimeException("visudo refused") })
        val model = model(CoroutineScope(coroutineContext), updates)
        val wanted = AutoUpdateSettings(CommandCatalog.Backups.Schedule.Days(1, 4, 0), setOf("adguard-home"))
        model.save(server(), wanted)
        runCurrent()

        assertTrue(model.state.value.schedule.schedule == CommandCatalog.Backups.Schedule.Off)
        assertEquals("visudo refused", model.state.value.errorMessage)
        assertTrue(!model.state.value.isSaving)
    }

    @Test
    fun `an accepted schedule becomes the shown one`() = runTest(StandardTestDispatcher()) {
        val updates = Scripted()
        val model = model(CoroutineScope(coroutineContext), updates)
        val wanted = AutoUpdateSettings(CommandCatalog.Backups.Schedule.Hours(6, 30), setOf("forgejo"))
        model.save(server(), wanted)
        runCurrent()

        assertEquals(wanted, updates.saved)
        assertEquals(wanted, model.state.value.schedule)
        assertNull(model.state.value.errorMessage)
    }

    // -------------------------------------------------------------- Running

    @Test
    fun `a rollback is reported as itself`() = runTest(StandardTestDispatcher()) {
        val updates = Scripted(run = { id, _ ->
            ServiceUpdateRunRecord(id, ServiceUpdateRunRecord.Outcome.RolledBack("did not come up"))
        })
        val model = model(CoroutineScope(coroutineContext), updates)
        model.run(server(), adguard)
        runCurrent()

        val run = model.state.value.run!!
        assertTrue(run.isFinished)
        assertEquals(ServiceUpdateRunRecord.Outcome.RolledBack("did not come up"), run.outcome)
        assertNull(run.errorMessage, "a rollback is not the app failing to run anything")
    }

    @Test
    fun `the log is the wrapper's output with its escape codes gone`() = runTest(StandardTestDispatcher()) {
        val updates = Scripted(run = { id, onChunk ->
            onChunk("[32mPulling adguardhome[0m\n")
            onChunk("done\n")
            ServiceUpdateRunRecord(id, ServiceUpdateRunRecord.Outcome.Updated)
        })
        val model = model(CoroutineScope(coroutineContext), updates)
        model.run(server(), adguard)
        runCurrent()

        assertEquals("Pulling adguardhome\ndone\n", model.state.value.run!!.log)
    }

    /**
     * **A service that has just been updated is no longer "update available".**
     * The row was drawn from a check that is now stale whichever way the run
     * ended, and the cheap honest answer is "not checked" — re-checking would
     * be a registry request per image of the whole server.
     */
    @Test
    fun `an updated service loses its stale answer`() = runTest(StandardTestDispatcher()) {
        val updates = Scripted(
            check = { listOf(ServiceUpdateReport(adguard, ServiceUpdateStatus.Available(listOf("x")))) },
        )
        val model = model(CoroutineScope(coroutineContext), updates)
        model.check(server(services = setOf(adguard)))
        runCurrent()
        assertTrue(model.state.value.reports[adguard] is ServiceUpdateStatus.Available)

        model.run(server(services = setOf(adguard)), adguard)
        runCurrent()

        assertNull(model.state.value.reports[adguard], "the old answer does not outlive the run")
    }

    /**
     * **The wrapper's markers are addressed to the app, not to the reader.**
     * Found on a live host: a finished Nextcloud update printed
     * `GRYONIXNEXUS_BACKUP_DONE 377608287 …` and `GRYONIXNEXUS_UPDATE_DONE
     * nextcloud` in the pane, around the docker lines somebody actually reads.
     * Built from the REAL tail of that run rather than from markers recalled
     * while writing the test — an invented fixture would contain exactly the
     * ones already remembered.
     */
    @Test
    fun `the protocol does not reach the log pane`() = runTest(StandardTestDispatcher()) {
        val real = "backing up nextcloud before updating it\n" +
            "GRYONIXNEXUS_BACKUP_DONE 377608287 /opt/backups/nextcloud/nextcloud-20260828-105118.tar.gz\n" +
            "GRYONIXNEXUS_BACKUP_CTL_DONE\n" +
            " Image nextcloud:apache Pulled\n" +
            " Container nextcloud-app-1 Running\n" +
            "GRYONIXNEXUS_UPDATE_DONE nextcloud\n" +
            "GRYONIXNEXUS_UPDATE_CTL_DONE\n"
        val updates = Scripted(run = { id, onChunk ->
            onChunk(real)
            ServiceUpdateRunRecord(id, ServiceUpdateRunRecord.Outcome.Updated)
        })
        val model = model(CoroutineScope(coroutineContext), updates)
        model.run(server(), adguard)
        runCurrent()

        val log = model.state.value.run!!.log
        assertTrue("GRYONIXNEXUS" !in log, "no marker survives: <${'$'}log>")
        assertTrue("backing up nextcloud before updating it" in log)
        assertTrue(" Container nextcloud-app-1 Running" in log, "what the reader came for stays")
    }

    @Test
    fun `the run log is re-read after a failed run`() = runTest(StandardTestDispatcher()) {
        val updates = Scripted(
            run = { _, _ -> throw RuntimeException("wrapper not installed") },
            status = {
                ServiceUpdateRunLog(
                    lastRun = Instant.parse("2026-08-28T04:00:00Z"),
                    records = listOf(ServiceUpdateRunRecord(adguard, ServiceUpdateRunRecord.Outcome.Updated)),
                )
            },
        )
        val model = model(CoroutineScope(coroutineContext), updates)
        model.run(server(), adguard)
        runCurrent()

        assertEquals("wrapper not installed", model.state.value.run!!.errorMessage)
        assertEquals(listOf("run:adguard-home", "status"), updates.asked)
        assertEquals(1, model.state.value.runLog.records.size)
    }

    // -------------------------------------------------------------- Schedule

    @Test
    fun `a reported service the record does not claim still gets a row`() {
        val deployment = server(services = setOf(adguard))
        val nextcloud = ServiceID("nextcloud")
        val reports = mapOf<ServiceID, ServiceUpdateStatus>(
            adguard to ServiceUpdateStatus.Current,
            nextcloud to ServiceUpdateStatus.Available(listOf("nextcloud:apache")),
        )

        assertEquals(listOf(adguard, nextcloud), UpdatesViewModel.rows(deployment, reports))
    }

    @Test
    fun `a service built on the server is not re-added by its own report`() {
        val deployment = server()
        val built = ServiceRegistry.all.first {
            it.updateSpec(deployment.serviceContext).flavour == UpdateSpec.Flavour.BUILT_ON_SERVER
        }
        val withBuilt = server(services = setOf(adguard, built.id))
        val reports = mapOf<ServiceID, ServiceUpdateStatus>(
            built.id to ServiceUpdateStatus.Current,
        )

        assertTrue(built.id !in UpdatesViewModel.rows(withBuilt, reports))
    }

    @Test
    fun `services built on the server are not offered to the timer`() {
        val deployment = server()
        val built = ServiceRegistry.all.first {
            it.updateSpec(deployment.serviceContext).flavour == UpdateSpec.Flavour.BUILT_ON_SERVER
        }
        val withBuilt = server(services = setOf(adguard, built.id))
        val offered = UpdatesViewModel.updatableServices(withBuilt).map { it.id }

        assertTrue(adguard in offered)
        assertTrue(built.id !in offered, "${built.id.rawValue} has no registry to ask")
    }
}
