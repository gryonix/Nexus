package com.skaymer.gryonixnexus.app.metrics

import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryBucket
import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryPoint
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class HistoryRangeTests {
    @Test
    fun `every window picks the bucket Swift picks`() {
        val golden = javaClass.getResourceAsStream("/swift-history-range.tsv")
            ?.bufferedReader()?.readText()
            ?: error("the golden is missing — run Tools/dump-history-range-golden.sh")
        val rows = golden.trim().lines().map { it.split("\t") }
        assertEquals(HistoryRange.entries.size, rows.size, "the golden and the port list different windows")

        for ((raw, span, bucket) in rows.map { Triple(it[0], it[1], it[2]) }) {
            val range = HistoryRange.of(raw) ?: error("no window called $raw")
            assertEquals(span.toLong(), range.spanSeconds, "span of $raw")
            assertEquals(bucket, range.bucket.rawValue, "bucket of $raw")
        }
    }

    /** Ten minutes must not read the minute file */
    @Test
    fun `the shortest windows read the finest file`() {
        assertEquals(MetricsHistoryBucket.TEN_SECONDS, HistoryRange.TEN_MINUTES.bucket)
        assertEquals(MetricsHistoryBucket.TEN_SECONDS, HistoryRange.THIRTY_MINUTES.bucket)
    }

    @Test
    fun `the long windows reach the long files`() {
        assertEquals(MetricsHistoryBucket.ONE_DAY, HistoryRange.MONTH.bucket)
        assertEquals(MetricsHistoryBucket.ONE_WEEK, HistoryRange.YEAR.bucket)
    }

    @Test
    fun `the refresh cadence is bounded at both ends`() {
        assertEquals(15, HistoryRange.TEN_MINUTES.refreshSeconds, "10s bucket: a quarter of it is below the floor")
        assertEquals(15, HistoryRange.HOUR.refreshSeconds, "1m bucket: a quarter of it IS the floor")
        assertEquals(60, HistoryRange.DAY.refreshSeconds, "10m bucket: a quarter of it is over the ceiling")
        assertEquals(60, HistoryRange.YEAR.refreshSeconds)
    }
}

class HistoryWindowTests {
    private fun point(secondsAgo: Long, from: Instant): MetricsHistoryPoint = MetricsHistoryPoint(
        date = from.minusSeconds(secondsAgo),
        cpuPercent = 10.0,
        memUsedBytes = 1,
        memTotalBytes = 2,
        diskUsedBytes = 1,
        diskTotalBytes = 2,
        netReceivedPerSecond = null,
        netSentPerSecond = null,
        diskReadPerSecond = null,
        diskWrittenPerSecond = null,
        load1 = 0.5,
        temperatureCelsius = null,
    )

    @Test
    fun `a stale server still fills its window`() {
        val now = Instant.parse("2026-08-27T12:00:00Z")
        val lastHeard = now.minusSeconds(7_200)
        val points = listOf(5_400L, 1_800L, 600L, 0L).map { point(it, lastHeard) }

        val windowed = points.windowed(HistoryRange.HOUR)
        assertEquals(3, windowed.size, "an hour before the newest row holds three of the four")
        assertTrue(windowed.last().date == lastHeard)

        val fromNow = points.filter { !it.date.isBefore(now.minusSeconds(3_600)) }
        assertTrue(fromNow.isEmpty())
    }

    @Test
    fun `an empty history windows to nothing rather than throwing`() {
        assertEquals(emptyList(), emptyList<MetricsHistoryPoint>().windowed(HistoryRange.DAY))
    }
}

class HistoryMetricTests {
    /** The percent group accumulates: three lines, one axis */
    @Test
    fun `percent metrics add up`() {
        var selection = setOf(HistoryMetric.CPU)
        selection = HistoryMetric.toggling(HistoryMetric.MEMORY, selection)
        selection = HistoryMetric.toggling(HistoryMetric.DISK, selection)
        assertEquals(setOf(HistoryMetric.CPU, HistoryMetric.MEMORY, HistoryMetric.DISK), selection)
        assertTrue(HistoryMetric.isPercentChart(selection))
    }

    /** Anything with its own unit REPLACES the selection */
    @Test
    fun `a unit metric takes the chart for itself`() {
        val selection = HistoryMetric.toggling(
            HistoryMetric.LOAD,
            setOf(HistoryMetric.CPU, HistoryMetric.MEMORY)
        )
        assertEquals(setOf(HistoryMetric.LOAD), selection)
        assertTrue(!HistoryMetric.isPercentChart(selection))
    }

    @Test
    fun `the selection never empties`() {
        assertEquals(setOf(HistoryMetric.CPU), HistoryMetric.toggling(HistoryMetric.CPU, setOf(HistoryMetric.CPU)))
    }

    @Test
    fun `the paired metrics give two series`() {
        val points = listOf(
            MetricsHistoryPoint(
                date = Instant.parse("2026-08-27T12:00:00Z"),
                cpuPercent = 12.0,
                memUsedBytes = 512, memTotalBytes = 1024,
                diskUsedBytes = 256, diskTotalBytes = 1024,
                netReceivedPerSecond = 100.0, netSentPerSecond = 50.0,
                diskReadPerSecond = 10.0, diskWrittenPerSecond = 20.0,
                load1 = 0.5, temperatureCelsius = null,
            )
        )
        val network = HistoryMetric.series(setOf(HistoryMetric.NETWORK), points)
        assertEquals(listOf("rx", "tx"), network.map { it.key })
        assertEquals(listOf(100.0, 50.0), network.map { it.values.single().value })
        assertEquals(1, HistoryMetric.series(setOf(HistoryMetric.LOAD), points).size)
    }

    /** The ceiling is labelled in the METRIC's unit */
    @Test
    fun `the axis says what the numbers are`() {
        assertEquals("0 – 100 %", HistoryMetric.axisLabel(setOf(HistoryMetric.CPU, HistoryMetric.MEMORY), 100.0))
        assertEquals("0 – 26.9 K/s", HistoryMetric.axisLabel(setOf(HistoryMetric.NETWORK), 27_562.0))
        assertEquals("0 – 26.9 K/s", HistoryMetric.axisLabel(setOf(HistoryMetric.DISK_IO), 27_562.0))
        assertEquals("0 – 45°C", HistoryMetric.axisLabel(setOf(HistoryMetric.TEMPERATURE), 45.0))
        assertEquals("0 – 2.4", HistoryMetric.axisLabel(setOf(HistoryMetric.LOAD), 2.4))
    }

    /** A missing value is left OUT, not plotted as zero */
    @Test
    fun `a sample with no value is absent rather than zero`() {
        val point = MetricsHistoryPoint(
            date = Instant.parse("2026-08-27T12:00:00Z"),
            cpuPercent = null,
            memUsedBytes = 512, memTotalBytes = 1024,
            diskUsedBytes = 256, diskTotalBytes = 1024,
            netReceivedPerSecond = null, netSentPerSecond = null,
            diskReadPerSecond = null, diskWrittenPerSecond = null,
            load1 = 0.5, temperatureCelsius = null,
        )
        assertTrue(HistoryMetric.series(setOf(HistoryMetric.CPU), listOf(point)).single().values.isEmpty())
        assertTrue(HistoryMetric.series(setOf(HistoryMetric.TEMPERATURE), listOf(point)).single().values.isEmpty())
        assertEquals(50.0, HistoryMetric.series(setOf(HistoryMetric.MEMORY), listOf(point)).single().values.single().value)
    }
}
