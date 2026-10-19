package com.skaymer.gryonixnexus.servercontrol

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class DiskHistoryTest {
    private val text = "120,/srv/data,300,1000\n100,/,50,100\nbroken\n100,/srv/data,100,1000\n120,/,60,100\n130,,1,2\n"

    @Test
    fun `rows parse in time order and bad ones are skipped`() {
        val points = DiskHistory.parse(text)
        assertEquals(4, points.size)
        assertEquals(listOf("/", "/srv/data"), DiskHistory.mounts(points))
    }

    @Test
    fun `average takes the mean percent at each moment`() {
        val line = DiskHistory.lines(DiskHistory.parse(text), DiskChoice.Average).single()
        assertEquals(listOf(30.0, 45.0), line.values.map { it.second })
    }

    @Test
    fun `each disk is its own line and one disk is only that`() {
        val points = DiskHistory.parse(text)
        val each = DiskHistory.lines(points, DiskChoice.Each)
        assertEquals(listOf("/", "/srv/data"), each.map { it.name })
        assertEquals(listOf(10.0, 30.0), each[1].values.map { it.second })
        assertEquals(listOf(50.0, 60.0), DiskHistory.lines(points, DiskChoice.One("/")).single().values.map { it.second })
    }
}
