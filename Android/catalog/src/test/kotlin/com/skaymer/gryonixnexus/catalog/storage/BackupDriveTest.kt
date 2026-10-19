package com.skaymer.gryonixnexus.catalog.storage

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class BackupDriveTest {
    private val uuid = "3f2a7c1e-5b8d-4e6f-9a0b-1c2d3e4f5a6b"

    private fun fixture(name: String): String =
        requireNotNull(javaClass.getResource("/storage/$name")).readText()

    @Test
    fun scriptsMatchTheAgent() {
        val identity = DiskIdentity("/dev/sdf", "4C530001", 61_530_439_680)
        assertEquals(fixture("drive-format.sh"), BackupDriveScripts.format("/dev/sdf", "usb1", identity))
        assertEquals(fixture("drive-attach.sh"), BackupDriveScripts.attach(uuid, "usb1"))
        assertEquals(fixture("drive-check.sh"), BackupDriveScripts.check(uuid, "usb1"))
        assertEquals(fixture("drive-eject.sh"), BackupDriveScripts.eject(uuid, "usb1"))
        assertEquals(fixture("drive-forget.sh"), BackupDriveScripts.forget(uuid, "usb1"))
    }

    @Test
    fun removableDrivesAreFoundAndTheSystemDiskIsNot() {
        val hardware = requireNotNull(ServerHardware.parse(fixture("probe-usb-drives.txt")))
        val drives = BackupDrives.drives(hardware, mapOf("dead-beef" to "usb9"))
        assertFalse(drives.any { it.disk?.path == "/dev/sda" }, "the system disk")
        assertFalse(drives.any { it.disk?.path == "/dev/sde" }, "mounted somewhere else")
        val blank = requireNotNull(drives.firstOrNull { it.disk?.path == "/dev/sdb" })
        assertEquals(BackupDrive.State.BLANK, blank.state)
        assertNull(blank.uuid)
        assertEquals(BackupDrive.State.READY, drives.first { it.uuid == uuid }.state)
        assertEquals(BackupDrive.State.UNMOUNTED, drives.first { it.name == "usb2" }.state)
        val missing = drives.first { it.uuid == "dead-beef" }
        assertEquals(BackupDrive.State.MISSING, missing.state)
        assertEquals("usb9", missing.name)
    }

    @Test
    fun namesAreChecked() {
        assertTrue(BackupDrives.isValidName("usb1"))
        assertTrue(BackupDrives.isValidName("backup-2"))
        assertFalse(BackupDrives.isValidName("USB"))
        assertFalse(BackupDrives.isValidName("-x"))
        assertFalse(BackupDrives.isValidName("twelve-chars"))
        assertEquals("usb3", BackupDrives.suggestedName(listOf("usb1", "usb2")))
    }

    @Test
    fun aCheckIsReadFromItsMarkers() {
        val check = BackupDriveCheck.parse(
            "GRYONIXNEXUS_DRIVE_SMART none\nGRYONIXNEXUS_DRIVE_FSCK clean\n" +
                "GRYONIXNEXUS_DRIVE_SPEED 31457280 104857600\nGRYONIXNEXUS_DRIVE_CHECK_DONE\n",
        )
        assertEquals(BackupDriveCheck.Smart.NONE, check.smart)
        assertEquals(BackupDriveCheck.Filesystem.CLEAN, check.filesystem)
        assertEquals(31_457_280L, check.writeBytesPerSecond)
        assertEquals(104_857_600L, check.readBytesPerSecond)
    }

    @Test
    fun theNewDrivesUuidIsReadAfterFormatting() {
        assertEquals(uuid, BackupDriveScripts.formattedUuid("x\nGRYONIXNEXUS_DRIVE_UUID $uuid\nGRYONIXNEXUS_DRIVE_FORMAT_DONE\n"))
        assertNotNull(BackupDriveScripts.formattedUuid("GRYONIXNEXUS_DRIVE_UUID $uuid"))
        assertTrue(BackupDriveScripts.isDriveCopy("/srv/gryonix-backup/usb1/nextcloud/a.tar.gz"))
        assertFalse(BackupDriveScripts.isDriveCopy("/srv/gryonix-backup/../etc/shadow"))
    }
}
