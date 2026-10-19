package com.skaymer.gryonixnexus.app.metrics

import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryPoint
import java.time.Instant
import java.time.ZoneOffset
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import org.junit.jupiter.api.Test

class EnergySummaryTests {
    private fun point(at: String, watts: Double?, source: String? = "rapl") = MetricsHistoryPoint(
        date = Instant.parse(at), cpuPercent = 10.0, memUsedBytes = 1, memTotalBytes = 2,
        diskUsedBytes = 1, diskTotalBytes = 2, netReceivedPerSecond = null, netSentPerSecond = null,
        diskReadPerSecond = null, diskWrittenPerSecond = null, load1 = 0.0, temperatureCelsius = null,
        powerWatts = watts, powerSource = source,
    )

    @Test
    fun `today, the month so far and last month add up from their buckets`() {
        val clock = Instant.parse("2026-09-16T12:00:00Z")
        val hourly = (0 until 12).map { point("2026-09-16T%02d:00:00Z".format(it), 100.0) }
        val daily = listOf(
            point("2026-08-31T00:00:00Z", 50.0),
            point("2026-09-01T00:00:00Z", 100.0),
            point("2026-09-15T00:00:00Z", 100.0),
        )
        val summary = EnergySummary.of(hourly.takeLast(1), hourly, daily, clock, ZoneOffset.UTC)
        assertEquals(1.2, summary.today, 1e-9)
        assertEquals(2.4 + 2.4 + 1.2, summary.monthSoFar, 1e-9)
        assertEquals(1.2, summary.lastMonth!!, 1e-9)
        assertEquals(100.0, summary.latest?.powerWatts)
        assertEquals(1.2, summary.days.last().second, 1e-9)
        assertEquals(6.0 + 100.0 * (720 - 60) / 1_000, summary.monthForecast, 1e-9)
    }

    @Test
    fun `an estimate alone is not called measured`() {
        val clock = Instant.parse("2026-09-16T12:00:00Z")
        val summary = EnergySummary.of(listOf(point("2026-09-16T11:59:50Z", 20.0, "estimate")), emptyList(), emptyList(), clock, ZoneOffset.UTC)
        assertFalse(summary.isMeasured)
    }
}
