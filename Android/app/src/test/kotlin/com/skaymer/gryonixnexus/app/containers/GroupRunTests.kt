package com.skaymer.gryonixnexus.app.containers

import kotlin.test.assertEquals
import org.junit.jupiter.api.Test

class GroupRunTests {
    @Test
    fun `the log keeps the newest lines and drops the oldest`() {
        var lines = emptyList<String>()
        repeat(LOG_LINE_LIMIT + 5) { lines = lines.appendBounded("line $it") }
        assertEquals(LOG_LINE_LIMIT, lines.size)
        assertEquals("line 5", lines.first())
        assertEquals("line ${LOG_LINE_LIMIT + 4}", lines.last())
    }

    @Test
    fun `a run that has not finished cannot be dismissed`() {
        val running = GroupRun(key = "stack", kind = GroupOperationKind.UPDATE)
        assertEquals(false, running.canBeDismissed)
        assertEquals(true, running.copy(isRunning = false).canBeDismissed)
    }

    // ---- The one refusal that turns into an offer -------------------------

    private fun failedUpdate(message: String) = GroupRun(
        key = "stack",
        kind = GroupOperationKind.UPDATE,
        isRunning = false,
        failure = message,
    )

    @Test
    fun `the empty-plan refusal offers the update without a backup`() {
        assertEquals(
            true,
            failedUpdate("nothing_to_archive: this group stores nothing outside its images")
                .mayUpdateWithoutBackup,
        )
    }

    @Test
    fun `a plan whose sources are gone is not offered the skip`() {
        assertEquals(
            false,
            failedUpdate("this plan names nothing that exists on the host — nothing was archived")
                .mayUpdateWithoutBackup,
        )
    }

    @Test
    fun `the marker is read at the front rather than anywhere`() {
        assertEquals(
            false,
            failedUpdate("backing up failed: nothing_to_archive: seen in a log line")
                .mayUpdateWithoutBackup,
        )
    }

    @Test
    fun `a run that did not fail offers nothing`() {
        assertEquals(
            false,
            GroupRun(key = "stack", kind = GroupOperationKind.UPDATE, isRunning = false)
                .mayUpdateWithoutBackup,
        )
    }

    @Test
    fun `the offer needs a finished update that has not already skipped`() {
        val refused = failedUpdate("nothing_to_archive: nothing outside the images")
        assertEquals(false, refused.copy(isRunning = true).mayUpdateWithoutBackup,
                     "offered while the run was still going")
        assertEquals(false, refused.copy(kind = GroupOperationKind.BACKUP).mayUpdateWithoutBackup,
                     "a backup has no backup to skip")
        assertEquals(false, refused.copy(kind = GroupOperationKind.REMOVE).mayUpdateWithoutBackup,
                     "a removal has no backup to skip")
        assertEquals(false, refused.copy(skippedBackup = true).mayUpdateWithoutBackup,
                     "offered again to a run that had already skipped the backup")
    }
}
