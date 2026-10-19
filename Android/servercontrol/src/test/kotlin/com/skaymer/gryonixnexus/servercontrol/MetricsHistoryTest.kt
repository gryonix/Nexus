package com.skaymer.gryonixnexus.servercontrol

import java.time.Instant
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertNull
import org.junit.jupiter.api.Test

class MetricsHistoryTest {
    // ------------------------------------------------------ Command literals

    @Test
    fun `the command reads the pinned collector path`() {
        assertEquals(
            "cat /var/lib/gryonixnexus/metrics/10s.csv 2>/dev/null; echo @@POWER@@; cat /var/lib/gryonixnexus/metrics/power-10s.csv 2>/dev/null; true",
            CommandCatalog.metricsHistory(MetricsHistoryBucket.TEN_SECONDS),
        )
        assertEquals(
            "cat /var/lib/gryonixnexus/metrics/1w.csv 2>/dev/null; echo @@POWER@@; cat /var/lib/gryonixnexus/metrics/power-1w.csv 2>/dev/null; true",
            CommandCatalog.metricsHistory(MetricsHistoryBucket.ONE_WEEK),
        )
    }

    @Test
    fun `the bucket names are the collector's file names`() {
        assertEquals(
            listOf("10s", "1m", "10m", "1h", "1d", "1w"),
            MetricsHistoryBucket.entries.map { it.rawValue },
        )
    }

    @Test
    fun `each bucket knows its own spacing`() {
        assertEquals(10.0, MetricsHistoryBucket.TEN_SECONDS.pointInterval)
        assertEquals(86_400.0, MetricsHistoryBucket.ONE_DAY.pointInterval)
        assertEquals(604_800.0, MetricsHistoryBucket.ONE_WEEK.pointInterval)
    }

    // ---------------------------------------------------------------- Parser

    @Test
    fun `a full row and a first-sample row both parse`() {
        val output = """
            1758000000,12.5,1073741824,2147483648,32000000000,110000000000,1024,2048,100,200,0.42,55.0
            1758000010,,1073741824,2147483648,32000000000,110000000000,,,,,0.42,
        """.trimIndent()
        val points = MetricsHistoryParser.parse(output)
        assertEquals(2, points.size)

        val full = points[0]
        assertEquals(Instant.ofEpochSecond(1_758_000_000), full.date)
        assertEquals(12.5, full.cpuPercent)
        assertEquals(1_073_741_824L, full.memUsedBytes)
        assertEquals(0.5, full.memUsedFraction)
        assertEquals(110_000_000_000L, full.diskTotalBytes)
        assertEquals(1024.0, full.netReceivedPerSecond)
        assertEquals(2048.0, full.netSentPerSecond)
        assertEquals(100.0, full.diskReadPerSecond)
        assertEquals(200.0, full.diskWrittenPerSecond)
        assertEquals(0.42, full.load1)
        assertEquals(55.0, full.temperatureCelsius)

        // First-sample row: no rates, no cpu, no temperature.
        val sparse = points[1]
        assertNull(sparse.cpuPercent)
        assertNull(sparse.netReceivedPerSecond)
        assertNull(sparse.diskWrittenPerSecond)
        assertNull(sparse.temperatureCelsius)
    }

    /**
     * A row the collector is writing at this very moment can arrive truncated,
     * and one bad row must not hide two weeks of good history.
     */
    @Test
    fun `malformed and truncated lines are skipped, not fatal`() {
        val output = """
            garbage
            1758000000,1.0,1,2,3,4,5,6,7,8,0.1,
            1758000010,1.0,1,2,3
            1758000020,1.0,1,2,3,4,5,6,7,8,not-a-number,
        """.trimIndent()
        val points = MetricsHistoryParser.parse(output)
        assertEquals(1, points.size)
        assertEquals(Instant.ofEpochSecond(1_758_000_000), points[0].date)
    }

    @Test
    fun `empty output means no history, not an error`() {
        assertEquals(emptyList(), MetricsHistoryParser.parse(""))
    }

    // ----------------------------------------------------------------- Probe

    @Test
    fun `the probe parses what the runner returned`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub(
            CommandCatalog.metricsHistory(MetricsHistoryBucket.ONE_MINUTE),
            stdout = "1758000000,50.0,1,2,3,4,5,6,7,8,1.00,\n",
        )
        val points = MetricsHistoryProbe(runner)
            .history(MetricsHistoryBucket.ONE_MINUTE, SSHHostID.VPS)
        assertEquals(1, points.size)
        assertEquals(50.0, points[0].cpuPercent)
    }

    /**
     * **The agent serves the history of the host IT RUNS ON.** In scenario B
     * that is the home machine, while the relay card is a different host with
     * its own collector and no agent — asking the agent for it would silently
     * return the home server's chart under the relay's name.
     */
    @Test
    fun `a host that is not the agent's own host reads over SSH`() {
        assertEquals(
            ServiceControlRoute.AGENT,
            MetricsHistoryRouting.route(
                usesAgent = true,
                agentTransportAvailable = true,
                host = SSHHostID.HOME,
                agentHost = SSHHostID.HOME,
            ),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            MetricsHistoryRouting.route(
                usesAgent = true,
                agentTransportAvailable = true,
                host = SSHHostID.VPS,
                agentHost = SSHHostID.HOME,
            ),
        )
    }
}
