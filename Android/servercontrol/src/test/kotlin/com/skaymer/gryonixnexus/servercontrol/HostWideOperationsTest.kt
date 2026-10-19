package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class HostWideOperationsTest {
    private fun singleWorker() = Deployment(
        id = "77777777-7777-7777-7777-777777777777",
        name = "A",
        topology = Topology.SINGLE_HOST,
        domain = "example.com",
        entry = HostEndpoint(host = "203.0.113.10", user = "root"),
        services = setOf(ServiceID.VAULTWARDEN),
    )

    private val thirdID = "88888888-8888-8888-8888-888888888888"

    private fun twoWorkers(): Deployment {
        val base = Deployment(
            id = "99999999-9999-9999-9999-999999999999",
            name = "B",
            topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
            domain = "example.com",
            entry = HostEndpoint(host = "203.0.113.10", user = "root"),
            homeWGAddress = "10.8.0.2",
            services = setOf(ServiceID.VAULTWARDEN, ServiceID.NEXTCLOUD),
        )
        val entry = base.nodes.first { it.legacySlot == DeploymentNode.LegacySlot.VPS }
        val third = DeploymentNode(
            id = thirdID,
            endpoint = HostEndpoint(host = "10.8.0.3", user = "root"),
            capabilities = setOf(NodeCapability.WORKER),
            routedThrough = entry.id,
        )
        return base.copy(storedNodes = base.nodes + third)
    }

    // ------------------------------------------- Which machines answer at all

    @Test
    fun `worker hosts is every machine that runs services`() {
        assertEquals(listOf(SSHHostID.VPS), singleWorker().workerHosts)

        val deployment = twoWorkers()
        assertEquals(listOf(SSHHostID.HOME, SSHHostID.node(thirdID)), deployment.workerHosts)
        assertFalse(
            deployment.workerHosts.contains(SSHHostID.VPS),
            "the relay runs nothing, so no host-wide question may be put to it",
        )
    }

    // ------------------------------------------------------------ The check

    @Test
    fun `the check asks one machine when there is only one`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("update-ctl.sh check", stdout = "GRYONIXNEXUS_UPDATE_CURRENT vaultwarden")

        val reports = ServiceUpdateOperations(runner, singleWorker()).check()

        assertEquals(listOf(SSHHostID.VPS), runner.calls.map { it.host })
        assertEquals(listOf(ServiceID.VAULTWARDEN), reports.map { it.service })
    }

    @Test
    fun `the check merges every worker's answer`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("update-ctl.sh check", stdout = "GRYONIXNEXUS_UPDATE_CURRENT vaultwarden")
        runner.stub(
            "update-ctl.sh check",
            stdout = "GRYONIXNEXUS_UPDATE_AVAILABLE nextcloud nextcloud:30-apache",
        )

        val reports = ServiceUpdateOperations(runner, twoWorkers()).check()

        assertEquals(
            listOf(SSHHostID.HOME, SSHHostID.node(thirdID)),
            runner.calls.map { it.host },
            "both workers, and never the relay",
        )
        assertEquals(
            listOf(ServiceID.VAULTWARDEN, ServiceID.NEXTCLOUD),
            reports.map { it.service },
        )
    }

    /**
     * The status file's `last-run` is a timestamp, so the answer is the MOST
     * RECENT across machines — not whichever machine was asked last.
     */
    @Test
    fun `the last run is the most recent across machines`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("update-ctl.sh status", stdout = "last-run 2026-08-07T19:44:21Z")
        runner.stub("update-ctl.sh status", stdout = "last-run 2026-08-01T03:00:00Z")

        val log = ServiceUpdateOperations(runner, twoWorkers()).loadStatus()

        assertEquals(Instant2026_08_07, log.lastRun)
    }

    private val Instant2026_08_07 get() = java.time.Instant.parse("2026-08-07T19:44:21Z")

    // ---------------------------------------------------------- The schedules

    @Test
    fun `a schedule on any worker reads as on`() {
        val merged = ServiceUpdateOperations.merged(
            listOf(
                AutoUpdateSettings(),
                AutoUpdateSettings(
                    schedule = CommandCatalog.Backups.Schedule.Days(count = 7, hour = 3, minute = 0),
                    services = setOf("nextcloud"),
                ),
            ),
        )
        assertTrue(merged.isOn)
        assertEquals(setOf("nextcloud"), merged.services)
        assertFalse(
            ServiceUpdateOperations.merged(listOf(AutoUpdateSettings(), AutoUpdateSettings())).isOn,
        )
    }

    @Test
    fun `the backup schedule keeps the largest retention and the union of services`() {
        val merged = AutoBackupOperations.merged(
            listOf(
                AutoBackupSettings(retention = 3, services = setOf("mailcow")),
                AutoBackupSettings(
                    schedule = CommandCatalog.Backups.Schedule.Days(count = 1, hour = 4, minute = 30),
                    retention = 30,
                    services = setOf("nextcloud"),
                ),
            ),
        )
        assertTrue(merged.isOn)
        assertEquals(30, merged.retention)
        assertEquals(setOf("mailcow", "nextcloud"), merged.services)
    }

    @Test
    fun `saving the update schedule arms every worker`() = runTest {
        val runner = FakeSSHCommandRunner()
        repeat(2) { runner.stub("update-ctl.sh set-schedule", stdout = "GRYONIXNEXUS_UPDATE_CTL_DONE\n") }

        ServiceUpdateOperations(runner, twoWorkers()).save(
            AutoUpdateSettings(
                schedule = CommandCatalog.Backups.Schedule.Days(count = 1, hour = 4, minute = 30),
                services = setOf("nextcloud"),
            ),
        )

        assertEquals(listOf(SSHHostID.HOME, SSHHostID.node(thirdID)), runner.calls.map { it.host })
    }

    @Test
    fun `saving the backup schedule arms every worker`() = runTest {
        val runner = FakeSSHCommandRunner()
        repeat(2) { runner.stub("backup-ctl.sh set-schedule", stdout = "GRYONIXNEXUS_BACKUP_CTL_DONE\n") }

        AutoBackupOperations(runner, twoWorkers()).save(
            AutoBackupSettings(
                schedule = CommandCatalog.Backups.Schedule.Days(count = 1, hour = 4, minute = 30),
                retention = 5,
                services = setOf("nextcloud"),
            ),
        )

        assertEquals(listOf(SSHHostID.HOME, SSHHostID.node(thirdID)), runner.calls.map { it.host })
    }

    @Test
    fun `a wrapper without destination verbs says what to do`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("backup-ctl.sh set-destination", exitCode = 2, stderr = "unsupported action: set-destination\n")

        val failure = assertFailsWith<ServerControlError> {
            AutoBackupOperations(runner, singleWorker()).saveDestination(
                BackupDestinationSettings(
                    kind = BackupDestinationSettings.Kind.SSH,
                    host = "backup.example",
                    user = "root",
                    path = "/backups",
                ),
            )
        }
        assertTrue(failure.message.orEmpty().contains("Repair server"), failure.message.orEmpty())
        assertTrue(!failure.message.orEmpty().contains("unsupported action"), failure.message.orEmpty())
    }

    @Test
    fun `testing a destination on an older wrapper says what to do`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("backup-ctl.sh test-destination", exitCode = 2, stderr = "unsupported action: test-destination\n")

        val result = AutoBackupOperations(runner, singleWorker()).testDestination()
        assertTrue(!result.succeeded)
        assertTrue(result.detail.contains("Repair server"), result.detail)
    }

    /** A partially armed fleet must not read as saved */
    @Test
    fun `a refusing worker fails the whole save`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("update-ctl.sh set-schedule", stdout = "GRYONIXNEXUS_UPDATE_CTL_DONE\n")
        runner.stub("update-ctl.sh set-schedule", exitCode = 1, stderr = "disk full")

        assertFailsWith<ServerControlError> {
            ServiceUpdateOperations(runner, twoWorkers()).save(
                AutoUpdateSettings(
                    schedule = CommandCatalog.Backups.Schedule.Days(count = 1, hour = 4, minute = 30),
                ),
            )
        }
    }

    /** The schedule config is shell-shaped `KEY=value`, quotes and all */
    @Test
    fun `the backup config parses and an absent one reads as off`() {
        val settings = AutoBackupOperations.parse(
            """
            SCHEDULE=every:1d@04:30
            RETENTION='14'
            SERVICES='mailcow nextcloud'
            """.trimIndent(),
        )
        assertTrue(settings.isOn)
        assertEquals(14, settings.retention)
        assertEquals(setOf("mailcow", "nextcloud"), settings.services)

        val absent = AutoBackupOperations.parse("")
        assertFalse(absent.isOn)
        assertEquals(7, absent.retention)
    }
}
