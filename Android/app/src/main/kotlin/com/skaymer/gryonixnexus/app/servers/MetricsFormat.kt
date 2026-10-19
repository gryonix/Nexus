package com.skaymer.gryonixnexus.app.servers

import kotlin.math.max
import kotlin.math.roundToLong

object MetricsFormat {
    fun bytes(value: Long): String {
        val units = listOf("B", "K", "M", "G", "T", "P")
        var scaled = max(0L, value).toDouble()
        var unit = 0
        while (scaled >= 1024 && unit < units.size - 1) {
            scaled /= 1024
            unit += 1
        }
        return "${trim(scaled)} ${units[unit]}"
    }

    fun percent(value: Double): String = "${fixed(value, 1)} %"

    fun load(value: Double): String = fixed(value, 1)

    fun temperature(celsius: Double): String = "${fixed(celsius, 0)}°C"

    /** "90d", "9d 11h", "5h 12m", "34m" — coarse on purpose */
    fun uptime(seconds: Double): String {
        val total = seconds.toLong()
        val days = total / 86_400
        val hours = (total % 86_400) / 3600
        val minutes = (total % 3600) / 60
        if (days >= 30) return "${days}d"
        if (days > 0) return "${days}d ${hours}h"
        if (hours > 0) return "${hours}h ${minutes}m"
        return "${minutes}m"
    }

    /** Per second, as the card says it: "1.2 M/s" */
    fun rate(bytesPerSecond: Double): String = "${bytes(bytesPerSecond.roundToLong())}/s"

    private fun trim(value: Double): String {
        val rounded = Math.round(value * 10) / 10.0
        return if (rounded == Math.floor(rounded)) fixed(rounded, 0) else fixed(rounded, 1)
    }

    private fun fixed(value: Double, scale: Int): String =
        java.math.BigDecimal(value)
            .setScale(scale, java.math.RoundingMode.HALF_EVEN)
            .toPlainString()
}
