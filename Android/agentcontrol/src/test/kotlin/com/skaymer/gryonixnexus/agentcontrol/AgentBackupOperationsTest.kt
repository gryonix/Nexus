package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.servercontrol.AgentServiceMapping
import com.skaymer.gryonixnexus.servercontrol.BackupListParser
import com.skaymer.gryonixnexus.servercontrol.BackupRouting
import com.skaymer.gryonixnexus.servercontrol.ServiceControlRoute
import com.skaymer.gryonixnexus.servercontrol.ServiceOperations
import gryonixnexusd.v1.BackupArchive
import gryonixnexusd.v1.BackupEncryption
import gryonixnexusd.v1.BackupEstimate
import gryonixnexusd.v1.BackupEvent
import gryonixnexusd.v1.AllBackups
import gryonixnexusd.v1.BackupList
import gryonixnexusd.v1.DeleteBackupRequest
import gryonixnexusd.v1.ListBackupsRequest
import gryonixnexusd.v1.RunBackupRequest
import gryonixnexusd.v1.ServiceOperationPhase
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of `AgentBackupOperationsTests` */
class AgentBackupOperationsTest {
    private fun service(id: ServiceID): ManagedService = checkNotNull(ServiceRegistry.service(id))

    private fun archive(path: String, bytes: Long, at: Long, directory: Boolean = false) = BackupArchive(
        name = path.substringAfterLast('/'),
        path = path,
        size_bytes = bytes,
        modified_at = at,
        directory = directory,
    )

    private fun event(
        phase: ServiceOperationPhase,
        text: String = "",
        announced: BackupArchive? = null,
        listing: List<BackupArchive>? = null,
    ) = BackupEvent(
        phase = phase,
        text = text,
        archive = announced,
        backups = listing?.let { BackupList(archives = it) },
    )

    private fun backups(transport: FakeAgentTransport) = AgentBackupOperations(AgentClient(transport))

    // ------------------------------------------------------------- Routing

    @Test
    fun `only the wrapper-driven flavour goes through the agent`() {
        assertEquals(
            ServiceControlRoute.AGENT,
            BackupRouting.route(true, agentTransportAvailable = true, kind = ServiceOperations.BackupKind.WRAPPER),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            BackupRouting.route(true, agentTransportAvailable = true, kind = ServiceOperations.BackupKind.ENCRYPTED),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            BackupRouting.route(true, agentTransportAvailable = true, kind = ServiceOperations.BackupKind.NONE),
        )
    }

    @Test
    fun `an agentless deployment keeps backing up over SSH`() {
        for (kind in ServiceOperations.BackupKind.entries) {
            assertEquals(
                ServiceControlRoute.SSH,
                BackupRouting.route(false, agentTransportAvailable = true, kind = kind),
            )
            assertEquals(
                ServiceControlRoute.SSH,
                BackupRouting.route(false, agentTransportAvailable = false, kind = kind),
            )
        }
        assertEquals(
            ServiceControlRoute.SSH,
            BackupRouting.route(true, agentTransportAvailable = false, kind = ServiceOperations.BackupKind.WRAPPER),
        )
    }

    // ------------------------------------------------------------- Listing

    @Test
    fun `listing carries absolute paths so delete and restore need no branch`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Backup/ListBackups",
            BackupList(
                service_id = "nextcloud",
                directory = "/opt/backups/nextcloud",
                archives = listOf(
                    archive("/opt/backups/nextcloud/nextcloud-20260806.tar.gz.gpg", 360_000_000, 1_754_400_000_000),
                    archive("/opt/backups/nextcloud/mailcow-20260805", 4096, 1_754_300_000_000, directory = true),
                ),
            ),
        )

        val entries = backups(transport).listBackups(service(ServiceID.NEXTCLOUD))

        assertEquals(listOf("/gryonixnexusd.v1.Backup/ListBackups"), transport.paths)
        assertEquals(
            "nextcloud",
            ListBackupsRequest.ADAPTER.decode(transport.calls.first().second).service_id,
            "the wire carries a catalog id, never a path",
        )
        assertEquals("/opt/backups/nextcloud/nextcloud-20260806.tar.gz.gpg", entries.first().name)
        assertEquals("nextcloud-20260806.tar.gz.gpg", entries.first().displayName)
        assertFalse(entries.first().isDirectory)
        assertTrue(entries.last().isDirectory)
        assertEquals("—", entries.last().sizeText)
        assertTrue(entries.first().sizeText.contains("MB"), entries.first().sizeText)
        assertTrue(entries.first().dateText.isNotEmpty())
    }

    @Test
    fun `one call lists every service without the cap`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Backup/ListAllBackups",
            AllBackups(
                lists = listOf(
                    BackupList(
                        service_id = "nextcloud",
                        archives = (0 until 15).map { archive("/opt/backups/nextcloud/n-$it.tar.gz", 10, it * 1000L) },
                    ),
                    BackupList(service_id = "vaultwarden"),
                ),
            ),
        )

        val listed = backups(transport).listAll()

        assertEquals(listOf("/gryonixnexusd.v1.Backup/ListAllBackups"), transport.paths)
        assertEquals(15, listed.getValue("nextcloud").size)
        assertEquals(0, listed.getValue("vaultwarden").size)
        assertEquals(10L, listed.getValue("nextcloud").first().sizeBytes)
    }

    @Test
    fun `the listing is capped the same way the SSH parser caps it`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Backup/ListBackups",
            BackupList(
                archives = (0 until 25).map {
                    archive("/opt/backups/immich/immich-$it.tar.gz", 10, (25L - it) * 1000)
                },
            ),
        )

        val entries = backups(transport).listBackups(service(ServiceID.IMMICH))

        assertEquals(BackupListParser.DEFAULT_LIMIT, entries.size)
        assertEquals("immich-0.tar.gz", entries.first().displayName)
    }

    // ------------------------------------------------------------ Estimate

    @Test
    fun `estimate arrives as bytes so the app decides what too big means`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Backup/EstimateBackup",
            BackupEstimate(data_bytes = 1_073_741_824, free_bytes = 223_338_299_392),
        )

        val result = backups(transport).estimate(service(ServiceID.NEXTCLOUD))

        assertEquals(listOf("/gryonixnexusd.v1.Backup/EstimateBackup"), transport.paths)
        assertNotNull(result)
        assertEquals(1_073_741_824, result.dataBytes)
        assertEquals(223_338_299_392, result.freeBytes)
        assertTrue(result.fitsOnDisk)
    }

    // ------------------------------------------------------------- Running

    @Test
    fun `a null encryption choice leaves the default to the wrapper`() = runTest {
        val cases = listOf(
            null to BackupEncryption.BACKUP_ENCRYPTION_UNSPECIFIED,
            true to BackupEncryption.BACKUP_ENCRYPTION_ENABLED,
            false to BackupEncryption.BACKUP_ENCRYPTION_DISABLED,
        )
        for ((choice, expected) in cases) {
            val transport = FakeAgentTransport()
            transport.stream("Backup/RunBackup")

            backups(transport).backup(service(ServiceID.NEXTCLOUD), encrypt = choice, passphrase = null) { }

            assertEquals(listOf("/gryonixnexusd.v1.Backup/RunBackup"), transport.paths)
            assertEquals(expected, RunBackupRequest.ADAPTER.decode(transport.calls.first().second).encryption)
        }
    }

    @Test
    fun `the passphrase travels as a request field not as a command line`() = runTest {
        val transport = FakeAgentTransport()
        transport.stream("Backup/RunBackup")

        backups(transport).backup(
            service(ServiceID.NEXTCLOUD),
            encrypt = true,
            passphrase = "correct horse battery staple",
        ) { }

        val sent = RunBackupRequest.ADAPTER.decode(transport.calls.first().second)
        assertEquals("correct horse battery staple", sent.passphrase)
        assertEquals("nextcloud", sent.service_id)
    }

    @Test
    fun `the announced archive and the streamed log both reach the caller`() = runTest {
        val announced = archive("/opt/backups/nextcloud/nextcloud-20260806.tar.gz", 4096, 1_754_400_000_000)
        val transport = FakeAgentTransport()
        transport.stream(
            "Backup/RunBackup",
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_STARTED),
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS, text = "dumping the nextcloud database"),
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS, text = "archiving"),
            event(
                ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED,
                announced = announced,
                listing = listOf(announced),
            ),
        )

        val chunks = mutableListOf<String>()
        val outcome = backups(transport)
            .backup(service(ServiceID.NEXTCLOUD), encrypt = false, passphrase = null) { chunks += it }

        assertEquals("/opt/backups/nextcloud/nextcloud-20260806.tar.gz", outcome.path)
        assertEquals(4096, outcome.sizeBytes)
        assertEquals(2, chunks.size, "only the progress lines are streamed")
        assertTrue(outcome.log.contains("archiving"), outcome.log)
    }

    @Test
    fun `a failed run still delivers the backup directory as re-read after it`() = runTest {
        val survivor = archive("/opt/backups/nextcloud/nextcloud-20260805.tar.gz", 900, 1_754_300_000_000)
        val transport = FakeAgentTransport()
        transport.streamThenFail(
            "Backup/RunBackup",
            AgentError.Rpc("internal", "the nextcloud database dump failed"),
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS, text = "archiving"),
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED, listing = listOf(survivor)),
        )

        val error = runCatching {
            backups(transport).backup(service(ServiceID.NEXTCLOUD), encrypt = null, passphrase = null) { }
        }.exceptionOrNull()

        assertTrue(error is AgentControlError.BackupFailed, "got $error")
        assertEquals(AgentError.Rpc("internal", "the nextcloud database dump failed"), error.underlying)
        assertEquals(listOf("nextcloud-20260805.tar.gz"), error.backups.map { it.displayName })
        assertEquals("the nextcloud database dump failed", error.message)
    }

    @Test
    fun `a run that failed leaving nothing still reports that it left nothing`() = runTest {
        val transport = FakeAgentTransport()
        transport.streamThenFail(
            "Backup/RunBackup",
            AgentError.Rpc("internal", "nextcloud backup failed"),
            event(
                ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS,
                text = "nextcloud has no data at /opt/nextcloud/data",
            ),
            event(ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED, listing = emptyList()),
        )

        val error = runCatching {
            backups(transport).backup(service(ServiceID.NEXTCLOUD), encrypt = null, passphrase = null) { }
        }.exceptionOrNull()

        assertTrue(error is AgentControlError.BackupFailed, "got $error")
        assertEquals(AgentError.Rpc("internal", "nextcloud backup failed"), error.underlying)
        assertTrue(error.backups.isEmpty(), "${error.backups}")
    }

    @Test
    fun `a refusal before anything ran keeps its own connect code`() = runTest {
        val refusal = AgentError.Rpc("failed_precondition", "this server has no backup wrapper")
        val transport = FakeAgentTransport()
        transport.fail("Backup/RunBackup", refusal)

        val error = runCatching {
            backups(transport).backup(service(ServiceID.NEXTCLOUD), encrypt = null, passphrase = null) { }
        }.exceptionOrNull()

        assertEquals(refusal, error)
    }

    // -------------------------------------------------------------- Delete

    @Test
    fun `delete sends the path the listing produced`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Backup/DeleteBackup", BackupList())

        backups(transport).deleteBackup(
            service(ServiceID.IMMICH),
            path = "/opt/backups/immich/immich-20260806.tar.gz",
        )

        assertEquals(listOf("/gryonixnexusd.v1.Backup/DeleteBackup"), transport.paths)
        val sent = DeleteBackupRequest.ADAPTER.decode(transport.calls.first().second)
        assertEquals("immich", sent.service_id)
        assertEquals("/opt/backups/immich/immich-20260806.tar.gz", sent.path)
    }

    // ---------------------------------------------------------- Addressing

    @Test
    fun `every catalog service is addressable by the agent`() {
        for (service in ServiceRegistry.all) {
            assertNotNull(AgentServiceMapping.agentID(service.id), "${service.id.rawValue} has no agent id")
        }
        for (id in ServiceID.VPN_PROTOCOLS + ServiceID.VPN_PANEL) {
            assertEquals("vpn", AgentServiceMapping.agentID(id), id.rawValue)
        }
        assertNull(AgentServiceMapping.agentID(ServiceID("some-future-service")))
    }
}
