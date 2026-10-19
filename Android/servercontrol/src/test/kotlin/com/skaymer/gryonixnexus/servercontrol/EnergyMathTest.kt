package com.skaymer.gryonixnexus.servercontrol

import java.time.Instant
import java.time.ZoneOffset
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class EnergyMathTest {
    private fun point(seconds: Long, cpu: Double?, watts: Double? = null) = MetricsHistoryPoint(
        date = Instant.ofEpochSecond(seconds), cpuPercent = cpu, memUsedBytes = 1, memTotalBytes = 2,
        diskUsedBytes = 1, diskTotalBytes = 2, netReceivedPerSecond = null, netSentPerSecond = null,
        diskReadPerSecond = null, diskWrittenPerSecond = null, load1 = 0.0, temperatureCelsius = null,
        powerWatts = watts,
    )

    @Test
    fun `the ssh output carries power on the same second`() {
        val output = "100,10,1,2,3,4,,,,,0.1,\n110,20,1,2,3,4,,,,,0.1,\n@@POWER@@\n110,33.5,rapl\njunk\n"
        val points = MetricsHistoryParser.parse(output)
        assertEquals(2, points.size)
        assertNull(points[0].powerWatts)
        assertEquals(33.5, points[1].powerWatts)
        assertEquals("rapl", points[1].powerSource)
        assertEquals(1, MetricsHistoryParser.parse("100,10,1,2,3,4,,,,,0.1,\n").size)
    }

    @Test
    fun `a measured point is kept and the rest is estimated`() {
        val filled = EnergyMath.filled(
            listOf(point(0, 50.0), point(10, 90.0, 80.0), point(20, null)),
            EnergyProfile(10.0, 50.0),
        )
        assertEquals(30.0, filled[0].powerWatts)
        assertEquals(EnergyMath.ESTIMATE_SOURCE, filled[0].powerSource)
        assertEquals(80.0, filled[1].powerWatts)
        assertNull(filled[2].powerWatts)
        assertTrue(EnergyMath.isMeasured(filled))
        assertFalse(EnergyMath.isMeasured(listOf(filled[0])))
    }

    @Test
    fun `one hour at one hundred watts is a tenth of a kilowatt-hour`() {
        val points = (0 until 60).map { point(it * 60L, null, 100.0) }
        val kwh = EnergyMath.kilowattHours(points, 60.0, Instant.ofEpochSecond(0), Instant.ofEpochSecond(3_600))
        assertEquals(0.1, kwh, 1e-9)
    }

    @Test
    fun `the forecast projects the average onto the whole month`() {
        val midnight = Instant.parse("2026-09-24T00:00:00Z")
        val now = midnight.plusSeconds(12 * 3_600)
        val hourly = (0 until 12).map { point(midnight.epochSecond + it * 3_600L, null, 50.0) }
        assertEquals(0.6 + 50.0 * (720 - 12) / 1_000, EnergyMath.monthForecast(emptyList(), hourly, now, ZoneOffset.UTC), 1e-9)
        assertEquals(0.0, EnergyMath.monthForecast(emptyList(), emptyList(), now, ZoneOffset.UTC), 1e-9)
    }
}
