package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.servercontrol.AutoBackupRouting
import com.skaymer.gryonixnexus.servercontrol.AutoBackupSettings
import com.skaymer.gryonixnexus.servercontrol.CommandCatalog
import com.skaymer.gryonixnexus.servercontrol.ServiceControlRoute
import gryonixnexusd.v1.BackupSchedulePolicy
import gryonixnexusd.v1.SetBackupScheduleRequest
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import org.junit.jupiter.api.Test

/** The Kotlin twin of `AgentAutoBackupOperationsTests` */
class AgentAutoBackupOperationsTest {
    private fun backups(transport: FakeAgentTransport) = AgentAutoBackupOperations(AgentClient(transport))

    // ------------------------------------------------------------- Routing

    @Test
    fun `backup schedule follows the same route as control actions`() {
        assertEquals(
            ServiceControlRoute.AGENT,
            AutoBackupRouting.route(usesAgent = true, agentTransportAvailable = true),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            AutoBackupRouting.route(usesAgent = true, agentTransportAvailable = false),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            AutoBackupRouting.route(usesAgent = false, agentTransportAvailable = true),
        )
    }

    // ---------------------------------------------------------------- Load

    @Test
    fun `load reads the schedule retention and services`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Backup/GetBackupSchedule",
            BackupSchedulePolicy(
                schedule = "every:1d@03:30",
                retention = 14,
                services = listOf("nextcloud", "vaultwarden"),
            ),
        )

        val settings = backups(transport).load()

        assertEquals(listOf("/gryonixnexusd.v1.Backup/GetBackupSchedule"), transport.paths)
        assertEquals(CommandCatalog.Backups.Schedule.Days(count = 1, hour = 3, minute = 30), settings.schedule)
        assertEquals(14, settings.retention)
        assertEquals(setOf("nextcloud", "vaultwarden"), settings.services)
    }

    @Test
    fun `load falls back to the default retention when the server names none`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Backup/GetBackupSchedule", BackupSchedulePolicy(schedule = "off"))

        val settings = backups(transport).load()

        assertEquals(AutoBackupSettings().retention, settings.retention)
    }

    // ---------------------------------------------------------------- Save

    @Test
    fun `save sends the grammar retention services and passphrase`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Backup/SetBackupSchedule", BackupSchedulePolicy())

        backups(transport).save(
            AutoBackupSettings(
                schedule = CommandCatalog.Backups.Schedule.Hours(count = 6, minute = 0),
                retention = 30,
                services = setOf("vaultwarden"),
            ),
            passphrase = "correct horse battery staple",
        )

        assertEquals(listOf("/gryonixnexusd.v1.Backup/SetBackupSchedule"), transport.paths)
        val sent = SetBackupScheduleRequest.ADAPTER.decode(transport.calls.first().second)
        assertEquals("every:6h@00:00", sent.schedule)
        assertEquals(30, sent.retention)
        assertEquals(listOf("vaultwarden"), sent.services)
        assertEquals("correct horse battery staple", sent.passphrase)
    }

    @Test
    fun `save sends an empty passphrase when none is given`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Backup/SetBackupSchedule", BackupSchedulePolicy())

        backups(transport).save(AutoBackupSettings(), passphrase = null)

        val sent = SetBackupScheduleRequest.ADAPTER.decode(transport.calls.first().second)
        assertEquals("", sent.passphrase)
    }
}
