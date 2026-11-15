package com.skaymer.gryonixnexus.app.notify

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class OperationJournalTest {
    private val day = 24L * 3600 * 1000

    @Test
    fun weeklyLinesKeepTheLastSevenDaysAndNameTheRun() {
        val now = 100 * day
        val entries = listOf(
            OperationJournal.Entry(now - 8 * day, "Update", "finished: old"),
            OperationJournal.Entry(now - day, "Update", "failed: no space"),
            OperationJournal.Entry(now - 1000, "", "job 12345678 started by the server"),
        )
        val lines = OperationJournal.recent(entries, now)
        assertEquals(2, lines.size)
        assertTrue(lines[0].endsWith(" [Update] failed: no space"))
        assertTrue(lines[1].endsWith(" job 12345678 started by the server"))
    }

    @Test
    fun theSummaryTakesAtMostSixtyLines() {
        val now = 10 * day
        val entries = (1..100).map { OperationJournal.Entry(now - it * 1000L, "", "e$it") }.reversed()
        val lines = OperationJournal.recent(entries, now)
        assertEquals(60, lines.size)
        assertTrue(lines.last().endsWith("e1"))
    }
}
