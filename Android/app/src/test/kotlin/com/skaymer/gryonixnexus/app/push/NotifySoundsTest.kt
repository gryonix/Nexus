package com.skaymer.gryonixnexus.app.push

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class NotifySoundsTest {
    @Test
    fun `each alert kind falls in the group the relay uses`() {
        assertEquals(NotifySoundGroup.DISKS, NotifySoundGroup.of("gnx.alert.raid"))
        assertEquals(NotifySoundGroup.DISKS, NotifySoundGroup.of("gnx.alert.drive_stale.ok"))
        assertEquals(NotifySoundGroup.BACKUPS, NotifySoundGroup.of("gnx.alert.backup.ok"))
        assertEquals(NotifySoundGroup.OPERATIONS, NotifySoundGroup.of("gnx.alert.operation.failed"))
        assertEquals(NotifySoundGroup.SSH, NotifySoundGroup.of("gnx.alert.ssh_login"))
        assertNull(NotifySoundGroup.of("gnx.alert.test"))
        assertNull(NotifySoundGroup.of("gnx.live"))
    }

    @Test
    fun `an unknown sound plays the system's`() {
        assertEquals(NotifySound.STANDARD, NotifySound.of("missing"))
        assertEquals(NotifySound.NONE, NotifySound.of("none"))
    }
}
