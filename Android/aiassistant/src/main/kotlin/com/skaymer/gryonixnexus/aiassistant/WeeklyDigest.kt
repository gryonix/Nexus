package com.skaymer.gryonixnexus.aiassistant

data class AIUsageSample(
    val timeMillis: Long,
    val cpuPercent: Double?,
    val memoryFraction: Double?,
    val diskFraction: Double?,
    val temperature: Double?,
)

/** Turns a week of samples into model text. */
object AIWeeklyDigest {
    fun lines(server: String, samples: List<AIUsageSample>): String {
        if (samples.isEmpty()) return "$server: no history"
        val sorted = samples.sortedBy { it.timeMillis }
        val parts = mutableListOf("$server: ${sorted.size} samples")
        stat(sorted.mapNotNull { it.cpuPercent })?.let { parts += "CPU avg %.0f%% max %.0f%%".format(it.first, it.second) }
        stat(sorted.mapNotNull { it.memoryFraction })?.let {
            parts += "memory avg %.0f%% max %.0f%%".format(it.first * 100, it.second * 100)
        }
        val disk = sorted.mapNotNull { it.diskFraction }
        if (disk.isNotEmpty()) parts += "disk %.0f%% -> %.0f%%".format(disk.first() * 100, disk.last() * 100)
        stat(sorted.mapNotNull { it.temperature })?.let { parts += "temperature max %.0f C".format(it.second) }
        return parts.joinToString(", ")
    }

    private fun stat(values: List<Double>): Pair<Double, Double>? =
        values.maxOrNull()?.let { values.average() to it }
}
