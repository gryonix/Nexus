package com.skaymer.gryonixnexus.app.ui

import com.skaymer.gryonixnexus.app.metrics.HistoryMetric
import com.skaymer.gryonixnexus.app.metrics.HistoryRange
import com.skaymer.gryonixnexus.app.metrics.MetricPanel
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals

class MetricsBoardReorderTests {
    private fun panel(id: String, server: String) = MetricPanel(
        id = id,
        deploymentID = server,
        hostRaw = "vps",
        metricsRaw = listOf(HistoryMetric.CPU.name),
        rangeRaw = HistoryRange.HOUR.name,
    )

    private val board = listOf(
        panel("a1", "alpha"),
        panel("b1", "beta"),
        panel("a2", "alpha"),
        panel("b2", "beta"),
        panel("a3", "alpha"),
    )

    @Test
    fun `unfiltered, a move is the plain swap it always was`() {
        assertEquals(
            listOf("b1", "a1", "a2", "b2", "a3"),
            movedWithinView(board, board, index = 0, by = 1).map { it.id },
        )
    }

    @Test
    fun `filtered, the two tiles swap where they actually live`() {
        val visible = board.filter { it.deploymentID == "alpha" }
        assertEquals(
            listOf("a2", "b1", "a1", "b2", "a3"),
            movedWithinView(board, visible, index = 0, by = 1).map { it.id },
        )
    }

    @Test
    fun `moving up from the top and down from the bottom change nothing`() {
        val visible = board.filter { it.deploymentID == "alpha" }
        assertEquals(board, movedWithinView(board, visible, index = 0, by = -1))
        assertEquals(board, movedWithinView(board, visible, index = 2, by = 1))
    }

    @Test
    fun `a tile the board has already lost moves nothing`() {
        val visible = listOf(panel("gone", "alpha"), board[0])
        assertEquals(board, movedWithinView(board, visible, index = 0, by = 1))
    }
}
