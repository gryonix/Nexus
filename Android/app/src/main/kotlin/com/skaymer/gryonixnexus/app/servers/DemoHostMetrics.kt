package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.servercontrol.DiskMount
import com.skaymer.gryonixnexus.servercontrol.HostMetricsSample
import com.skaymer.gryonixnexus.servercontrol.HostMetricsSnapshot
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import kotlin.math.sin

/** What kind of machine a demo server pretends to be */
data class DemoMachineProfile(
    val cores: Int,
    val memTotalBytes: Long,
    val diskTotalBytes: Long,
    val diskUsedFraction: Double,
    val cpuBusy: Double,
    val cpuSwing: Double,
    val memUsedFraction: Double,
    val memSwing: Double,
    val netReceivedPerSecond: Double,
    val netSentPerSecond: Double,
    val diskReadPerSecond: Double,
    val diskWrittenPerSecond: Double,
    val temperatureCelsius: Double?,
    val uptimeDays: Double,
    val osID: String,
    val osPrettyName: String,
) {
    companion object {
        private const val GB = 1_073_741_824L

        val BUSY_HOST = DemoMachineProfile(
            4, 8 * GB, 160 * GB, 0.52, 0.34, 0.12, 0.61, 0.06,
            1_400_000.0, 520_000.0, 900_000.0, 2_100_000.0, null, 47.0, "ubuntu", "Ubuntu 24.04 LTS",
        )
        val RELAY = DemoMachineProfile(
            1, GB, 20 * GB, 0.27, 0.07, 0.05, 0.38, 0.04,
            3_600_000.0, 3_400_000.0, 40_000.0, 120_000.0, null, 132.0, "debian", "Debian GNU/Linux 12",
        )
        val HOME_BACKEND = DemoMachineProfile(
            6, 16 * GB, 1000 * GB, 0.58, 0.23, 0.14, 0.49, 0.07,
            3_100_000.0, 2_800_000.0, 5_600_000.0, 3_400_000.0, 54.0, 23.0, "debian", "Debian GNU/Linux 12",
        )
        val MEDIA_VAULT = DemoMachineProfile(
            4, 8 * GB, 4000 * GB, 0.78, 0.16, 0.20, 0.44, 0.05,
            260_000.0, 6_200_000.0, 11_000_000.0, 700_000.0, 47.0, 96.0, "raspbian", "Raspberry Pi OS",
        )
        val SMALL_LAB = DemoMachineProfile(
            2, 4 * GB, 80 * GB, 0.31, 0.11, 0.07, 0.52, 0.05,
            180_000.0, 90_000.0, 300_000.0, 400_000.0, null, 9.0, "ubuntu", "Ubuntu 24.04 LTS",
        )
    }
}

object DemoHostMetrics {
    private const val TICK_SECONDS = 5.0

    fun covers(deploymentID: String): Boolean = DemoDeployments.isDemoID(deploymentID)

    fun profile(deploymentID: String, host: SSHHostID): DemoMachineProfile =
        when (deploymentID.takeLast(1)) {
            "2" -> if (host == SSHHostID.HOME) DemoMachineProfile.HOME_BACKEND else DemoMachineProfile.RELAY
            "3" -> DemoMachineProfile.MEDIA_VAULT
            "4" -> DemoMachineProfile.SMALL_LAB
            else -> DemoMachineProfile.BUSY_HOST
        }

    fun snapshot(deploymentID: String, host: SSHHostID, tick: Long): HostMetricsSnapshot {
        val machine = profile(deploymentID, host)
        val seed = seed(deploymentID, host)
        val current = sample(machine, seed, tick)
        val previous = if (tick > 0) sample(machine, seed, tick - 1) else null
        return HostMetricsSnapshot.from(current, previous)
    }

    private fun seed(deploymentID: String, host: SSHHostID): Long {
        var value = -0x340d631b7bdddcdbL
        (deploymentID + host.toString()).toByteArray().forEach { byte ->
            value = (value xor (byte.toLong() and 0xff)) * 0x100000001b3L
        }
        return value
    }

    private fun wander(seed: Long, salt: Double, tick: Long): Double {
        val phase = Math.floorMod(seed, 628L) / 100.0
        val t = tick.toDouble()
        return 0.6 * sin(t / 7 + phase + salt) + 0.4 * sin(t / 23 + phase * 2 + salt)
    }

    private fun sample(profile: DemoMachineProfile, seed: Long, tick: Long): HostMetricsSample {
        fun busy(at: Long) = (profile.cpuBusy + profile.cpuSwing * wander(seed, 0.4, at)).coerceIn(0.01, 0.98)
        fun counter(perSecond: Double, salt: Double, offset: Double): Long {
            val sinceStart = (0 until tick).sumOf { at ->
                perSecond * (0.7 + 0.3 * (0.5 + 0.5 * wander(seed, salt, at))) * TICK_SECONDS
            }
            return (perSecond * minOf(profile.uptimeDays, 7.0) * 86_400 * offset + sinceStart).toLong()
        }
        val memUsed = (profile.memUsedFraction + profile.memSwing * wander(seed, 1.7, tick)).coerceIn(0.05, 0.97)
        val load = profile.cores * busy(tick)
        return HostMetricsSample(
            cpuTotalTicks = tick * 1000,
            cpuIdleTicks = ((0 until tick).sumOf { 1 - busy(it) } * 1000).toLong(),
            cpuCores = profile.cores,
            memTotalBytes = profile.memTotalBytes,
            memUsedBytes = (profile.memTotalBytes * memUsed).toLong(),
            swapTotalBytes = profile.memTotalBytes / 4,
            swapUsedBytes = profile.memTotalBytes / 40,
            uptimeSeconds = profile.uptimeDays * 86_400 + tick * TICK_SECONDS,
            load1 = load,
            load5 = load * 0.85 + 0.05,
            load15 = load * 0.7 + 0.05,
            netReceivedBytes = counter(profile.netReceivedPerSecond, 2.9, 0.6),
            netSentBytes = counter(profile.netSentPerSecond, 4.1, 0.6),
            diskReadBytes = counter(profile.diskReadPerSecond, 5.3, 0.4),
            diskWrittenBytes = counter(profile.diskWrittenPerSecond, 6.7, 0.4),
            mounts = listOf(
                DiskMount("/", profile.diskTotalBytes, (profile.diskTotalBytes * profile.diskUsedFraction).toLong(), 0)
            ),
            osID = profile.osID,
            osPrettyName = profile.osPrettyName,
            temperatureCelsius = profile.temperatureCelsius?.let { it + 3 * wander(seed, 9.1, tick) },
        )
    }
}
