package com.skaymer.gryonixnexus.servercontrol

import java.time.LocalDateTime
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class BackupOverviewTest {
    private fun row(
        server: String, service: String, name: String, bytes: Long? = null,
        at: Long? = null, drive: String? = null, directory: Boolean = false,
    ) = FleetBackup(
        server, "srv-$server", service, service,
        BackupEntry(name, "", "", directory, drive, bytes, at),
    )

    @Test
    fun newestComesFirstAndUndatedStayLastInOrder() {
        val rows = listOf(
            row("1", "a", "old", at = 10), row("1", "a", "none1"),
            row("2", "b", "new", at = 30), row("1", "a", "none2"),
        )
        assertEquals(listOf("new", "old", "none1", "none2"), BackupOverview.sorted(rows).map { it.entry.name })
    }

    @Test
    fun filterNarrowsByServiceAndPlace() {
        val rows = listOf(row("1", "a", "x"), row("1", "b", "y", drive = "usb"), row("2", "a", "z"))
        assertEquals(2, BackupOverview.filtered(rows, BackupFilter(serviceId = "a")).size)
        assertEquals(listOf("y"), BackupOverview.filtered(rows, BackupFilter(place = BackupFilter.Place.DRIVES)).map { it.entry.name })
        assertEquals(2, BackupOverview.filtered(rows, BackupFilter(place = BackupFilter.Place.SERVER)).size)
    }

    @Test
    fun aPlaceAdmitsServerCopiesDriveCopiesOrBoth() {
        val onServer = BackupEntry("a", "", "")
        val onDrive = BackupEntry("b", "", "", drive = "usb")
        assertEquals(listOf(true, true), listOf(onServer, onDrive).map { BackupFilter.Place.ANY.admits(it) })
        assertEquals(listOf(true, false), listOf(onServer, onDrive).map { BackupFilter.Place.SERVER.admits(it) })
        assertEquals(listOf(false, true), listOf(onServer, onDrive).map { BackupFilter.Place.DRIVES.admits(it) })
    }

    @Test
    fun totalsCountSizesDrivesAndTheNewest() {
        val rows = listOf(
            row("1", "a", "x", bytes = 100, at = 5), row("1", "a", "y", bytes = 50, at = 9, drive = "usb"),
            row("2", "a", "z"), row("2", "a", "dir", directory = true),
        )
        val totals = BackupOverview.totals(rows)
        assertEquals(BackupTotals(count = 4, bytes = 150, onDrives = 1, newestMillis = 9, unsized = 1), totals)
    }

    @Test
    fun lsSizesBecomeBytes() {
        assertEquals(512L, BackupListParser.approximateBytes("512"))
        assertEquals(2048L, BackupListParser.approximateBytes("2.0K"))
        assertEquals(1_572_864L, BackupListParser.approximateBytes("1.5M"))
        assertNull(BackupListParser.approximateBytes("—"))
    }

    @Test
    fun aListedFileCarriesItsSizeAndTime() {
        val line = "-rw------- 1 root root 3.0M Oct  9 03:00 /opt/backups/x/a.tar.gz"
        val entry = BackupListParser.parse(line).first()
        assertEquals(3L shl 20, entry.sizeBytes)
        assertEquals(false, entry.modifiedAtMillis == null)
    }

    @Test
    fun aTimeMeansThisYearUnlessThatIsInTheFuture() {
        val zone = ZoneId.of("UTC")
        val now = LocalDateTime.of(2026, 10, 10, 12, 0)
        val recent = BackupListParser.approximateDate(listOf("Oct", "9", "03:00"), now, zone)!!
        val late = BackupListParser.approximateDate(listOf("Dec", "30", "03:00"), now, zone)!!
        assertEquals(2026, java.time.Instant.ofEpochMilli(recent).atZone(zone).year)
        assertEquals(2025, java.time.Instant.ofEpochMilli(late).atZone(zone).year)
        assertNull(BackupListParser.approximateDate(listOf("Foo", "5", "2024"), now, zone))
    }
}
