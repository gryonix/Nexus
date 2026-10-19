package com.skaymer.gryonixnexus.servercontrol

/** Raw counters read in one probe pass */
data class HostMetricsSample(
    /** Aggregate jiffies from the first `cpu` line of /proc/stat */
    var cpuTotalTicks: Long = 0,
    /** idle + iowait jiffies */
    var cpuIdleTicks: Long = 0,
    var cpuCores: Int = 0,
    /** MemTotal / (MemTotal - MemAvailable) from /proc/meminfo, in bytes */
    var memTotalBytes: Long = 0,
    var memUsedBytes: Long = 0,
    var swapTotalBytes: Long = 0,
    var swapUsedBytes: Long = 0,
    var uptimeSeconds: Double = 0.0,
    var load1: Double = 0.0,
    var load5: Double = 0.0,
    var load15: Double = 0.0,
    /** Bytes since boot, summed over every interface except loopback */
    var netReceivedBytes: Long = 0,
    var netSentBytes: Long = 0,
    var diskReadBytes: Long = 0,
    var diskWrittenBytes: Long = 0,
    var mounts: List<DiskMount> = emptyList(),
    /** ID= / PRETTY_NAME= from /etc/os-release, when present */
    var osID: String? = null,
    var osPrettyName: String? = null,
    /** Hottest thermal zone, degrees C */
    var temperatureCelsius: Double? = null,
)

data class HostMetricsSnapshot(
    val cpuCores: Int,
    /** 0..100; null until two samples exist */
    val cpuPercent: Double?,
    val memTotalBytes: Long,
    val memUsedBytes: Long,
    val swapTotalBytes: Long,
    val swapUsedBytes: Long,
    val diskTotalBytes: Long,
    val diskUsedBytes: Long,
    val uptimeSeconds: Double,
    val load1: Double,
    val load5: Double,
    val load15: Double,
    /** Since-boot totals, always available */
    val netReceivedBytes: Long,
    val netSentBytes: Long,
    val diskReadBytes: Long,
    val diskWrittenBytes: Long,
    /** Bytes per second; null until two samples exist */
    val netReceivedPerSecond: Double?,
    val netSentPerSecond: Double?,
    val diskReadPerSecond: Double?,
    val diskWrittenPerSecond: Double?,
    val osID: String?,
    val osPrettyName: String?,
    val temperatureCelsius: Double?,
    val isPartial: Boolean,
) {
    val memUsedFraction: Double
        get() = if (memTotalBytes > 0) memUsedBytes.toDouble() / memTotalBytes.toDouble() else 0.0

    val diskUsedFraction: Double
        get() = if (diskTotalBytes > 0) diskUsedBytes.toDouble() / diskTotalBytes.toDouble() else 0.0

    companion object {
        fun from(current: HostMetricsSample, previous: HostMetricsSample?): HostMetricsSnapshot {
            val root = current.mounts.firstOrNull { it.target == "/" }
                ?: current.mounts.maxByOrNull { it.sizeBytes }

            val elapsed = previous?.let { current.uptimeSeconds - it.uptimeSeconds } ?: 0.0
            var cpuPercent: Double? = null
            var netReceivedPerSecond: Double? = null
            var netSentPerSecond: Double? = null
            var diskReadPerSecond: Double? = null
            var diskWrittenPerSecond: Double? = null
            if (previous != null && elapsed > 0) {
                val totalDelta = current.cpuTotalTicks - previous.cpuTotalTicks
                val idleDelta = current.cpuIdleTicks - previous.cpuIdleTicks
                cpuPercent = if (totalDelta > 0) {
                    ((totalDelta - idleDelta).toDouble() / totalDelta.toDouble() * 100)
                        .coerceIn(0.0, 100.0)
                } else {
                    null
                }
                fun rate(currentValue: Long, previousValue: Long): Double =
                    maxOf(0.0, (currentValue - previousValue).toDouble() / elapsed)
                netReceivedPerSecond = rate(current.netReceivedBytes, previous.netReceivedBytes)
                netSentPerSecond = rate(current.netSentBytes, previous.netSentBytes)
                diskReadPerSecond = rate(current.diskReadBytes, previous.diskReadBytes)
                diskWrittenPerSecond = rate(current.diskWrittenBytes, previous.diskWrittenBytes)
            }

            return HostMetricsSnapshot(
                cpuCores = current.cpuCores,
                cpuPercent = cpuPercent,
                memTotalBytes = current.memTotalBytes,
                memUsedBytes = current.memUsedBytes,
                swapTotalBytes = current.swapTotalBytes,
                swapUsedBytes = current.swapUsedBytes,
                diskTotalBytes = root?.sizeBytes ?: 0,
                diskUsedBytes = root?.usedBytes ?: 0,
                uptimeSeconds = current.uptimeSeconds,
                load1 = current.load1,
                load5 = current.load5,
                load15 = current.load15,
                netReceivedBytes = current.netReceivedBytes,
                netSentBytes = current.netSentBytes,
                diskReadBytes = current.diskReadBytes,
                diskWrittenBytes = current.diskWrittenBytes,
                netReceivedPerSecond = netReceivedPerSecond,
                netSentPerSecond = netSentPerSecond,
                diskReadPerSecond = diskReadPerSecond,
                diskWrittenPerSecond = diskWrittenPerSecond,
                osID = current.osID,
                osPrettyName = current.osPrettyName,
                temperatureCelsius = current.temperatureCelsius,
                isPartial = false,
            )
        }

        fun fromCollectorRow(point: MetricsHistoryPoint): HostMetricsSnapshot =
            HostMetricsSnapshot(
                cpuCores = 0,
                cpuPercent = point.cpuPercent,
                memTotalBytes = point.memTotalBytes,
                memUsedBytes = point.memUsedBytes,
                swapTotalBytes = 0,
                swapUsedBytes = 0,
                diskTotalBytes = point.diskTotalBytes,
                diskUsedBytes = point.diskUsedBytes,
                uptimeSeconds = 0.0,
                load1 = point.load1,
                load5 = 0.0,
                load15 = 0.0,
                netReceivedBytes = 0,
                netSentBytes = 0,
                diskReadBytes = 0,
                diskWrittenBytes = 0,
                netReceivedPerSecond = point.netReceivedPerSecond,
                netSentPerSecond = point.netSentPerSecond,
                diskReadPerSecond = point.diskReadPerSecond,
                diskWrittenPerSecond = point.diskWrittenPerSecond,
                osID = null,
                osPrettyName = null,
                temperatureCelsius = point.temperatureCelsius,
                isPartial = true,
            )
    }
}
