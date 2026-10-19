package com.skaymer.gryonixnexus.servercontrol

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class SystemUpdateTest {
    /** Real output of the updater on a server */
    private val finished = """
        state=idle
        exit=0
        finished=1790629350
        reboot=no
        system=on
        apps=off
        log:
        Reading state information...
        0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
        GRYONIXNEXUS_SYSTEM_EXIT:0

    """.trimIndent()

    private val fresh = "state=idle\nexit=\nfinished=0\nreboot=no\nsystem=off\napps=off\nlog:\n"

    @Test
    fun `a finished run reads its code log and switches`() {
        val status = requireNotNull(SystemUpdateStatus.parse(finished))
        assertFalse(status.isRunning)
        assertEquals(0, status.exitCode)
        assertEquals(1_790_629_350L, status.finished)
        assertTrue(status.systemAtStart)
        assertFalse(status.appsAtStart)
        assertEquals("0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.", status.log.last())
    }

    @Test
    fun `a host that never ran has no code or date`() {
        val status = requireNotNull(SystemUpdateStatus.parse(fresh))
        assertNull(status.exitCode)
        assertNull(status.finished)
        assertTrue(status.log.isEmpty())
        assertNull(SystemUpdateStatus.parse("sudo: a password is required\n"))
    }

    @Test
    fun `swap is read and set`() {
        val status = requireNotNull(SystemUpdateStatus.parse("state=idle\nswap=2147479552\nswapfile=2147483648\nlog:\n"))
        assertEquals(2_147_479_552L, status.swapBytes)
        assertEquals(2_147_483_648L, status.swapFileBytes)
        assertEquals("sudo -n /opt/gryonixnexus-system-ctl.sh swap 4", SystemUpdate.swapCommand(4))
        assertEquals("sudo -n /opt/gryonixnexus-system-ctl.sh swap off", SystemUpdate.swapCommand(null))
    }

    @Test
    fun `commands name the script and its arguments`() {
        assertEquals(
            "sudo -n /opt/gryonixnexus-system-ctl.sh at-start apps on",
            SystemUpdate.atStartCommand(SystemUpdate.Part.APPS, true),
        )
        assertTrue(SystemUpdate.isMissing(ExecResult(1, "", "sudo: a password is required\n")))
        assertFalse(SystemUpdate.isMissing(ExecResult(1, "", "E: dpkg was interrupted")))
    }

    @Test
    fun `shutdown switches show only when the updater knows them`() {
        val old = requireNotNull(SystemUpdateStatus.parse("state=idle\nsystem=off\napps=off\nlog:\n"))
        assertFalse(old.offersAtStop)
        val new = requireNotNull(SystemUpdateStatus.parse("state=idle\nsystem_stop=on\napps_stop=off\nlog:\n"))
        assertTrue(new.offersAtStop)
        assertTrue(new.systemAtStop)
        assertFalse(new.appsAtStop)
        assertEquals(
            "sudo -n /opt/gryonixnexus-system-ctl.sh at-stop system off",
            SystemUpdate.atStopCommand(SystemUpdate.Part.SYSTEM, false),
        )
    }

    @Test
    fun `sudo refusing the grant reads as a missing updater`() {
        val refusal = "sudo: I'm sorry server-user. I'm afraid I can't do that\n"
        assertTrue(SystemUpdate.isMissing(ExecResult(1, "", refusal)))
    }

    @Test
    fun `the schedule is read and sent`() {
        assertEquals(null, SystemUpdateStatus.parse("state=idle\nlog:\n")?.schedule)
        assertEquals(CommandCatalog.Backups.Schedule.Off, SystemUpdateStatus.parse("schedule=off\nlog:\n")?.schedule)
        val weekly = CommandCatalog.Backups.Schedule.Days(count = 7, hour = 3, minute = 30)
        assertEquals(weekly, SystemUpdateStatus.parse("schedule=every:7d@03:30\nlog:\n")?.schedule)
        assertEquals(
            "sudo -n /opt/gryonixnexus-system-ctl.sh schedule every:7d@03:30",
            SystemUpdate.scheduleCommand(weekly),
        )
    }
}
