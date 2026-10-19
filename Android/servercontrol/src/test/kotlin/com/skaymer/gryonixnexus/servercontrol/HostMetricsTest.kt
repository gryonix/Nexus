package com.skaymer.gryonixnexus.servercontrol

import java.util.Locale
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class HostMetricsTest {
    /** A realistic probe output for a small Debian VPS */
    private fun probeOutput(
        cpuUser: Int = 1000,
        cpuIdle: Int = 8000,
        cpuIOWait: Int = 200,
        netRx: Int = 1_000_000,
        netTx: Int = 500_000,
        sectorsRead: Int = 2000,
        sectorsWritten: Int = 4000,
        uptime: Double = 7_776_000.0,
    ): String = """
        @@STAT@@
        cpu  $cpuUser 50 300 $cpuIdle $cpuIOWait 0 25 10 0 0
        cpu0 500 25 150 4000 100 0 12 5 0 0
        cpu1 500 25 150 4000 100 0 13 5 0 0
        intr 12345
        @@MEM@@
        MemTotal:         430080 kB
        MemFree:           51200 kB
        MemAvailable:     174080 kB
        Buffers:           20480 kB
        Cached:            81920 kB
        SwapTotal:        102400 kB
        SwapFree:          92160 kB
        @@UPTIME@@
        ${String.format(Locale.ROOT, "%.2f", uptime + 0.35)} 15130655.92
        @@LOAD@@
        0.42 0.31 0.25 1/123 4567
        @@NET@@
        Inter-|   Receive                                                |  Transmit
         face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
            lo: 999999    9999    0    0    0     0          0         0  999999    9999    0    0    0     0       0          0
          eth0: $netRx   66666    0    0    0     0          0         0 $netTx   55555    0    0    0     0       0          0
        @@DISKSTATS@@
           8       0 sda 5000 100 $sectorsRead 3000 7000 200 $sectorsWritten 9000 0 5000 12000 0 0 0 0
           8       1 sda1 4900 90 999999 2900 6900 190 999999 8900 0 4900 11800 0 0 0 0
         254       0 dm-0 100 0 500 50 100 0 500 60 0 100 110 0 0 0 0
        @@DF@@
        Mounted on     1B-blocks       Used Use%
        /            45000000000 5364000000  12%
        /boot         512000000   52000000   11%
        @@OS@@
        PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
        NAME="Debian GNU/Linux"
        ID=debian
        @@NPROC@@
        2
        @@TEMP@@
        42500
        38000
    """.trimIndent()

    @Test
    fun `the whole probe output parses`() {
        val sample = HostMetricsParser.parse(probeOutput())

        // cpu line: 1000+50+300+8000+200+0+25+10 = 9585; idle 8000+200 = 8200.
        assertEquals(9585L, sample.cpuTotalTicks)
        assertEquals(8200L, sample.cpuIdleTicks)
        assertEquals(2, sample.cpuCores)

        assertEquals(430_080L * 1024, sample.memTotalBytes)
        assertEquals((430_080L - 174_080) * 1024, sample.memUsedBytes)
        assertEquals(102_400L * 1024, sample.swapTotalBytes)
        assertEquals(10_240L * 1024, sample.swapUsedBytes)

        assertEquals(7_776_000.35, sample.uptimeSeconds, 0.01)
        assertEquals(0.42, sample.load1, 0.001)
        assertEquals(0.25, sample.load15, 0.001)

        // lo is excluded.
        assertEquals(1_000_000L, sample.netReceivedBytes)
        assertEquals(500_000L, sample.netSentBytes)

        // Only sda counts: partitions (sda1) and dm-0 are excluded.
        assertEquals(2000L * 512, sample.diskReadBytes)
        assertEquals(4000L * 512, sample.diskWrittenBytes)

        assertEquals(2, sample.mounts.size)
        assertEquals("debian", sample.osID)
        assertEquals("Debian GNU/Linux 12 (bookworm)", sample.osPrettyName)
        assertEquals(42.5, sample.temperatureCelsius ?: 0.0, 0.01)
    }

    @Test
    fun `nvme and virtio disks count, their partitions do not`() {
        val output = probeOutput()
            .replace(
                "   8       0 sda 5000 100 2000 3000 7000 200 4000 9000 0 5000 12000 0 0 0 0",
                "   259     0 nvme0n1 5000 100 1000 3000 7000 200 1000 9000 0 5000 12000 0 0 0 0\n" +
                    "   259     1 nvme0n1p1 100 0 999 50 100 0 999 60 0 100 110 0 0 0 0\n" +
                    "   254     0 vda 100 0 500 50 100 0 500 60 0 100 110 0 0 0 0",
            )
            .replace(
                "   8       1 sda1 4900 90 999999 2900 6900 190 999999 8900 0 4900 11800 0 0 0 0\n",
                "",
            )
        val sample = HostMetricsParser.parse(output)
        assertEquals((1000L + 500) * 512, sample.diskReadBytes)
        assertEquals((1000L + 500) * 512, sample.diskWrittenBytes)
    }

    @Test
    fun `a stripped host still parses`() {
        // No os-release, no thermal zones, empty df.
        val output = """
            @@STAT@@
            cpu  100 0 50 800 50 0 0 0 0 0
            cpu0 100 0 50 800 50 0 0 0 0 0
            @@MEM@@
            MemTotal:  1024000 kB
            MemAvailable: 512000 kB
            @@UPTIME@@
            123.45 100.00
            @@LOAD@@
            @@NET@@
            @@DISKSTATS@@
            @@DF@@
            @@OS@@
            @@NPROC@@
            @@TEMP@@
        """.trimIndent()
        val sample = HostMetricsParser.parse(output)
        assertEquals(1, sample.cpuCores)
        assertNull(sample.temperatureCelsius)
        assertNull(sample.osID)
        assertTrue(sample.mounts.isEmpty())
        assertEquals(512_000L * 1024, sample.memUsedBytes)
    }

    @Test
    fun `a probe missing cpu, memory or uptime is unusable`() {
        assertFailsWith<ServerControlError.ParseFailure> {
            HostMetricsParser.parse("@@MEM@@\nMemTotal: 1 kB")
        }
        assertFailsWith<ServerControlError.ParseFailure> { HostMetricsParser.parse("") }
    }

    // -------------------------------------------------------- Snapshot/rates

    @Test
    fun `the first snapshot has absolute values but no rates`() {
        val snapshot = HostMetricsSnapshot.from(HostMetricsParser.parse(probeOutput()), null)
        assertNull(snapshot.cpuPercent)
        assertNull(snapshot.netReceivedPerSecond)
        assertNull(snapshot.diskWrittenPerSecond)
        // Absolute values are present immediately.
        assertEquals(45_000_000_000L, snapshot.diskTotalBytes)
        assertEquals(5_364_000_000L, snapshot.diskUsedBytes)
        assertEquals(1_000_000L, snapshot.netReceivedBytes)
    }

    @Test
    fun `the second snapshot computes the rates`() {
        val first = HostMetricsParser.parse(probeOutput())
        val second = HostMetricsParser.parse(
            probeOutput(
                cpuUser = 2000, cpuIdle = 8900, cpuIOWait = 300,
                netRx = 3_000_000, netTx = 1_500_000,
                sectorsRead = 4000, sectorsWritten = 6000,
                uptime = 7_776_010.0,
            ),
        )
        val snapshot = HostMetricsSnapshot.from(second, first)

        assertEquals(50.0, snapshot.cpuPercent ?: -1.0, 0.1)
        assertEquals(200_000.0, snapshot.netReceivedPerSecond ?: -1.0, 1.0)
        assertEquals(100_000.0, snapshot.netSentPerSecond ?: -1.0, 1.0)
        assertEquals(2000.0 * 512 / 10, snapshot.diskReadPerSecond ?: -1.0, 1.0)
        assertEquals(2000.0 * 512 / 10, snapshot.diskWrittenPerSecond ?: -1.0, 1.0)
    }

    @Test
    fun `a reboot between samples drops the rates`() {
        val first = HostMetricsParser.parse(probeOutput(uptime = 7_776_000.0))
        val second = HostMetricsParser.parse(probeOutput(uptime = 60.0))
        val snapshot = HostMetricsSnapshot.from(second, first)
        assertNull(snapshot.cpuPercent)
        assertNull(snapshot.netReceivedPerSecond)
    }

    @Test
    fun `a collector row fills the card and says it is partial`() {
        val point = MetricsHistoryParser.parse(
            "1758000000,12.5,1073741824,2147483648,32000000000,110000000000,1024,2048,100,200,0.42,55.0",
        ).single()
        val snapshot = HostMetricsSnapshot.fromCollectorRow(point)
        assertTrue(snapshot.isPartial)
        assertEquals(12.5, snapshot.cpuPercent)
        assertEquals(1024.0, snapshot.netReceivedPerSecond)
        assertEquals(0.42, snapshot.load1)
        // A row carries no uptime and no since-boot totals.
        assertEquals(0.0, snapshot.uptimeSeconds)
        assertEquals(0L, snapshot.netReceivedBytes)
        assertNull(snapshot.osPrettyName)
    }

    // ----------------------------------------------------------------- Probe

    @Test
    fun `the probe runs the catalog command and parses its answer`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("@@STAT@@", stdout = probeOutput())
        val sample = HostMetricsProbe(runner).sample(SSHHostID.VPS)
        assertEquals(2, sample.cpuCores)
        assertEquals(
            listOf(
                FakeSSHCommandRunner.Call(
                    FakeSSHCommandRunner.CallKind.RUN,
                    CommandCatalog.HOST_METRICS,
                    SSHHostID.VPS,
                ),
            ),
            runner.calls,
        )
    }

    @Test
    fun `the probe surfaces a command failure instead of parsing nothing`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("", stdout = "", exitCode = 127)
        assertFailsWith<ServerControlError.CommandFailed> {
            HostMetricsProbe(runner).sample(SSHHostID.HOME)
        }
    }
}
