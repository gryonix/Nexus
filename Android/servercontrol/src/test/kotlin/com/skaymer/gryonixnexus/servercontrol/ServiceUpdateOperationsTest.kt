package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceUpdateStatus
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The update wrapper's markers, parsed */
class ServiceUpdateOperationsTest {
    // ------------------------------------------------------------ The check

    @Test
    fun `a service with nothing to do reads as current`() {
        val reports = ServiceUpdateOperations.parseCheck("GRYONIXNEXUS_UPDATE_CURRENT nextcloud")
        assertEquals(listOf(ServiceID.NEXTCLOUD), reports.map { it.service })
        assertEquals(ServiceUpdateStatus.Current, reports[0].status)
    }

    @Test
    fun `every moved image is carried through by name`() {
        val reports = ServiceUpdateOperations.parseCheck(
            """
            GRYONIXNEXUS_UPDATE_AVAILABLE nextcloud nextcloud:30-apache
            GRYONIXNEXUS_UPDATE_AVAILABLE nextcloud mariadb:11
            """.trimIndent(),
        )
        assertEquals(1, reports.size)
        assertEquals(
            ServiceUpdateStatus.Available(listOf("nextcloud:30-apache", "mariadb:11")),
            reports[0].status,
        )
    }

    @Test
    fun `an unreachable registry is not current`() {
        val reports = ServiceUpdateOperations.parseCheck("GRYONIXNEXUS_UPDATE_UNKNOWN immich")
        assertEquals(ServiceUpdateStatus.Unknown, reports[0].status)
    }

    @Test
    fun `one moved image outweighs the rest of the stack being current`() {
        val reports = ServiceUpdateOperations.parseCheck(
            """
            GRYONIXNEXUS_UPDATE_CURRENT nextcloud
            GRYONIXNEXUS_UPDATE_AVAILABLE nextcloud mariadb:11
            """.trimIndent(),
        )
        assertEquals(ServiceUpdateStatus.Available(listOf("mariadb:11")), reports[0].status)
    }

    @Test
    fun `an id this build does not know is still reported`() {
        val reports = ServiceUpdateOperations.parseCheck("GRYONIXNEXUS_UPDATE_CURRENT some-future-thing")
        assertEquals(listOf("some-future-thing"), reports.map { it.service.rawValue })
    }

    @Test
    fun `prose between the markers is ignored`() {
        val reports = ServiceUpdateOperations.parseCheck(
            """
            checking nextcloud…
            GRYONIXNEXUS_UPDATE_CURRENT nextcloud
            pulling registry.example/immich:latest
            GRYONIXNEXUS_UPDATE_CURRENT immich
            """.trimIndent(),
        )
        assertEquals(listOf(ServiceID.NEXTCLOUD, ServiceID.IMMICH), reports.map { it.service })
    }

    @Test
    fun `a truncated marker is not a status`() {
        assertEquals(emptyList(), ServiceUpdateOperations.parseCheck("GRYONIXNEXUS_UPDATE_AVAILABLE nextcloud"))
        assertEquals(emptyList(), ServiceUpdateOperations.parseCheck("GRYONIXNEXUS_UPDATE_CURRENT"))
    }

    // ---------------------------------------------------------- The schedule

    @Test
    fun `an absent config reads as off`() {
        assertEquals(AutoUpdateSettings(), ServiceUpdateOperations.parseSchedule(""))
    }

    @Test
    fun `the stored schedule and service list are read`() {
        val settings = ServiceUpdateOperations.parseSchedule(
            """
            SCHEDULE=every:1d@03:30
            SERVICES="jellyfin nextcloud"
            """.trimIndent(),
        )
        assertTrue(settings.isOn)
        assertEquals(setOf("jellyfin", "nextcloud"), settings.services)
    }

    @Test
    fun `an unparsable schedule reads as off`() {
        val settings = ServiceUpdateOperations.parseSchedule("SCHEDULE=every-other-tuesday")
        assertEquals(CommandCatalog.Backups.Schedule.Off, settings.schedule)
    }

    // ------------------------------------------------------- The status file

    @Test
    fun `the live status file sample is read in full detail`() {
        val log = ServiceUpdateOperations.parseStatus(
            """
            last-run 2026-08-07T19:44:21Z
            GRYONIXNEXUS_UPDATE_DONE jellyfin
            GRYONIXNEXUS_UPDATE_ROLLED_BACK jellyfin a container is still starting
            GRYONIXNEXUS_UPDATE_FAILED adguard-home the backup was refused
            """.trimIndent(),
        )
        assertEquals(Instant.parse("2026-08-07T19:44:21Z"), log.lastRun)
        assertEquals(
            listOf(
                ServiceUpdateRunRecord(ServiceID.JELLYFIN, ServiceUpdateRunRecord.Outcome.Updated),
                ServiceUpdateRunRecord(
                    ServiceID.JELLYFIN,
                    ServiceUpdateRunRecord.Outcome.RolledBack("a container is still starting"),
                ),
                ServiceUpdateRunRecord(
                    ServiceID("adguard-home"),
                    ServiceUpdateRunRecord.Outcome.Failed("the backup was refused"),
                ),
            ),
            log.records,
        )
    }

    @Test
    fun `a manual run with no last-run line still yields its records`() {
        val log = ServiceUpdateOperations.parseStatus("GRYONIXNEXUS_UPDATE_DONE nextcloud")
        assertNull(log.lastRun)
        assertEquals(
            listOf(ServiceUpdateRunRecord(ServiceID.NEXTCLOUD, ServiceUpdateRunRecord.Outcome.Updated)),
            log.records,
        )
    }

    @Test
    fun `an empty file reads as an empty log`() {
        assertTrue(ServiceUpdateOperations.parseStatus("").isEmpty)
    }

    /** The reason is everything after the service id, space-joined */
    @Test
    fun `a reason with several words is kept whole`() {
        val log = ServiceUpdateOperations.parseStatus(
            "GRYONIXNEXUS_UPDATE_ROLLED_BACK immich a container is still starting after the deadline",
        )
        assertEquals(
            ServiceUpdateRunRecord.Outcome.RolledBack(
                "a container is still starting after the deadline",
            ),
            log.records.single().outcome,
        )
    }

    @Test
    fun `a malformed timestamp still leaves the records readable`() {
        val log = ServiceUpdateOperations.parseStatus(
            """
            last-run not-a-date
            GRYONIXNEXUS_UPDATE_DONE nextcloud
            """.trimIndent(),
        )
        assertNull(log.lastRun)
        assertEquals(1, log.records.size)
    }
}
