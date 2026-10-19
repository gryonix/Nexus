package com.skaymer.gryonixnexus.servercontrol

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class BackupDrivesParsingTest {
    @Test
    fun showDrivesIsRead() {
        val state = BackupDrivesParsing.parse(
            """
            DRIVE_MODE=drive
            DRIVE_ENCRYPT=0
            DRIVES=aa-11 bb-22
            DRIVE_PASS=1
            DRIVE=aa-11 1 61530439680 30000000000 /srv/gryonix-backup/usb1
            DRIVE=bb-22 0 0 0 /srv/gryonix-backup/usb2
            DRIVE_AT=1700000000
            DRIVE_OK=0
            DRIVE_ERROR='usb2: not connected;'
            GRYONIXNEXUS_BACKUP_CTL_DONE
            """.trimIndent(),
        )
        assertEquals(BackupDriveSettings.Mode.DRIVE, state.settings.mode)
        assertFalse(state.settings.encrypt)
        assertEquals(listOf("aa-11", "bb-22"), state.settings.uuids)
        assertTrue(state.hasPassphrase)
        assertEquals(2, state.statuses.size)
        assertTrue(state.statuses[0].mounted)
        assertEquals(30_000_000_000L, state.statuses[0].freeBytes)
        assertEquals("usb2", state.namesByUuid["bb-22"])
        assertFalse(state.lastCopySucceeded)
        assertEquals("usb2: not connected;", state.lastError)
        assertEquals(1_700_000_000L, state.lastCopyAt)
    }

    @Test
    fun aFreshServerEncryptsByDefault() {
        val state = BackupDrivesParsing.parse("GRYONIXNEXUS_BACKUP_CTL_DONE\n")
        assertEquals(BackupDriveSettings.Mode.BOTH, state.settings.mode)
        assertTrue(state.settings.encrypt)
        assertTrue(state.settings.uuids.isEmpty())
    }

    @Test
    fun setDrivesQuotesEveryArgument() {
        assertEquals(
            "sudo /opt/gryonixnexus-backup-ctl.sh set-drives 'both' '1' 'aa-11'",
            CommandCatalog.Backups.setDrives("both", true, listOf("aa-11")),
        )
    }

    @Test
    fun formattingReplacesTheDrivesOldFilesystem() {
        val state = BackupDrivesState(
            settings = BackupDriveSettings(uuids = listOf("old-1", "other-2", "stale-3")),
            statuses = listOf(
                BackupDriveStatus("old-1", mountPoint = "/srv/gryonix-backup/usb1"),
                BackupDriveStatus("other-2", mountPoint = "/srv/gryonix-backup/usb2"),
                BackupDriveStatus("stale-3", mountPoint = "/srv/gryonix-backup/usb3"),
            ),
        )
        assertEquals(listOf("other-2", "new-4"), state.settingsAfterFormat("new-4", "old-1", "usb3").uuids)
        assertEquals(listOf("old-1", "other-2", "stale-3", "new-4"), state.settingsAfterFormat("new-4", null, "usb9").uuids)
    }

    @Test
    fun aDriveWithoutMountPointIsUnmapped() {
        val state = BackupDrivesState(
            statuses = listOf(BackupDriveStatus("aa", mountPoint = "/srv/gryonix-backup/usb1"), BackupDriveStatus("bb")),
        )
        assertFalse(state.isUnmapped("aa"))
        assertTrue(state.isUnmapped("bb"))
        assertTrue(state.isUnmapped("cc"))
    }
}
