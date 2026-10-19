package com.skaymer.gryonixnexus.servercontrol

import java.time.Instant

data class MetricsHistoryPoint(
    val date: Instant,
    val cpuPercent: Double?,
    val memUsedBytes: Long,
    val memTotalBytes: Long,
    val diskUsedBytes: Long,
    val diskTotalBytes: Long,
    val netReceivedPerSecond: Double?,
    val netSentPerSecond: Double?,
    val diskReadPerSecond: Double?,
    val diskWrittenPerSecond: Double?,
    val load1: Double,
    val temperatureCelsius: Double?,
    /** Watts from the host's own sensor, when it has one */
    val powerWatts: Double? = null,
    /** The sensor: rapl, hwmon, ipmi, ups or pi */
    val powerSource: String? = null,
) {
    val memUsedFraction: Double
        get() = if (memTotalBytes > 0) memUsedBytes.toDouble() / memTotalBytes.toDouble() else 0.0

    val diskUsedFraction: Double
        get() = if (diskTotalBytes > 0) diskUsedBytes.toDouble() / diskTotalBytes.toDouble() else 0.0
}

object MetricsHistoryParser {
    const val POWER_MARKER = "@@POWER@@"

    fun parse(output: String): List<MetricsHistoryPoint> {
        val sections = output.split(POWER_MARKER)
        val points = sections[0].split("\n").filter { it.isNotEmpty() }.mapNotNull(::parseLine)
        return if (sections.size > 1) attachPower(sections[1], points) else points
    }

    /** Joins `epoch,watts,sensor` rows onto the points of the same second */
    fun attachPower(text: String, points: List<MetricsHistoryPoint>): List<MetricsHistoryPoint> {
        val readings = text.split("\n").mapNotNull { line ->
            val fields = line.split(",")
            val epoch = fields.getOrNull(0)?.trim()?.toLongOrNull() ?: return@mapNotNull null
            val watts = fields.getOrNull(1)?.trim()?.toDoubleOrNull() ?: return@mapNotNull null
            epoch to (watts to fields.getOrNull(2)?.trim().orEmpty())
        }.toMap()
        return points.map { point ->
            val reading = readings[point.date.epochSecond] ?: return@map point
            point.copy(powerWatts = reading.first, powerSource = reading.second)
        }
    }

    private fun parseLine(line: String): MetricsHistoryPoint? {
        val fields = line.split(",")
        if (fields.size != 12) return null
        val epoch = fields[0].toDoubleOrNull() ?: return null
        val memUsed = fields[2].toLongOrNull() ?: return null
        val memTotal = fields[3].toLongOrNull() ?: return null
        val diskUsed = fields[4].toLongOrNull() ?: return null
        val diskTotal = fields[5].toLongOrNull() ?: return null
        val load1 = fields[10].toDoubleOrNull() ?: return null

        fun optionalDouble(field: String): Double? = if (field.isEmpty()) null else field.toDoubleOrNull()

        return MetricsHistoryPoint(
            date = instantOf(epoch),
            cpuPercent = optionalDouble(fields[1]),
            memUsedBytes = memUsed,
            memTotalBytes = memTotal,
            diskUsedBytes = diskUsed,
            diskTotalBytes = diskTotal,
            netReceivedPerSecond = optionalDouble(fields[6]),
            netSentPerSecond = optionalDouble(fields[7]),
            diskReadPerSecond = optionalDouble(fields[8]),
            diskWrittenPerSecond = optionalDouble(fields[9]),
            load1 = load1,
            temperatureCelsius = optionalDouble(fields[11]),
        )
    }

    private fun instantOf(epoch: Double): Instant {
        val seconds = Math.floor(epoch).toLong()
        val nanos = Math.round((epoch - seconds) * 1_000_000_000)
        return Instant.ofEpochSecond(seconds, nanos)
    }
}
