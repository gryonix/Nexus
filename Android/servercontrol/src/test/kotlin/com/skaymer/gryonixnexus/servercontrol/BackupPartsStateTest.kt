package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.BackupPart
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class BackupPartsStateTest {
    @Test
    fun `a service keeps its own lines and borrows the rest`() {
        val state = BackupPartsParsing.state(
            "BACKUP_PARTS='databases'\nUPDATE_PARTS='settings databases'\n" +
                "UPDATE_PARTS_minecraft_java='files'\nBACKUP_PARTS_Bad='files'\n",
        )
        assertEquals(setOf("minecraft-java"), state.services.keys)
        assertEquals(setOf(BackupPart.FILES), state.choiceFor("minecraft-java").beforeUpdate)
        assertEquals(setOf(BackupPart.DATABASES), state.choiceFor("minecraft-java").regular)
        assertEquals(state.choice, state.choiceFor("immich"))
        assertEquals(
            "sudo /opt/gryonixnexus-backup-ctl.sh set-parts 'backup' '--service' 'immich' 'files'",
            CommandCatalog.Backups.setParts("backup", listOf("files"), "immich"),
        )
    }

    @Test
    fun `the shared switch follows every service and sets them all`() {
        val listed = listOf("immich", "nextcloud")
        var state = BackupPartsState()
        assertTrue(state.sharedIsOn(BackupPart.FILES, BackupPartScope.REGULAR, listed))
        state = state.applying(state.settingService("immich", BackupPart.FILES, BackupPartScope.REGULAR, false))
        assertFalse(state.sharedIsOn(BackupPart.FILES, BackupPartScope.REGULAR, listed))
        assertTrue(BackupPart.FILES in state.choiceFor("nextcloud").regular)
        val change = state.settingShared(BackupPart.FILES, BackupPartScope.REGULAR, true, listed)
        assertEquals(listed.toSet(), change.services.keys)
        state = state.applying(change)
        assertTrue(state.sharedIsOn(BackupPart.FILES, BackupPartScope.REGULAR, listed))
        assertEquals(setOf(BackupPart.SETTINGS, BackupPart.DATABASES), state.choiceFor("immich").beforeUpdate)
    }
}
