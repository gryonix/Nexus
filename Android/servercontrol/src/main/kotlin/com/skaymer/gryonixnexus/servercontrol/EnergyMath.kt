package com.skaymer.gryonixnexus.servercontrol

import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters
import kotlinx.serialization.Serializable

/** Idle and full-load watts for hosts without a sensor */
@Serializable
data class EnergyProfile(val idleWatts: Double, val peakWatts: Double) {
    fun watts(cpuPercent: Double): Double {
        val load = cpuPercent.coerceIn(0.0, 100.0) / 100
        return idleWatts + (peakWatts - idleWatts) * load
    }

    companion object {
        /** A starting guess from the core count */
        fun guess(cores: Int): EnergyProfile {
            val count = maxOf(cores, 1).toDouble()
            val idle = 8 + count
            return EnergyProfile(idle, minOf(idle + 6 * count, 400.0))
        }
    }
}

/** Watts, energy and money from history points */
object EnergyMath {
    const val ESTIMATE_SOURCE = "estimate"

    /** Suffix of a partial reading completed from the estimate */
    const val COMPLETED_SUFFIX = "+estimate"

    /** Estimates missing points, completes partial sensor readings */
    fun filled(
        points: List<MetricsHistoryPoint>,
        profile: EnergyProfile,
        estimate: PowerEstimate? = null,
    ): List<MetricsHistoryPoint> = points.map { point ->
        val watts = point.powerWatts
        val cpu = point.cpuPercent
        val source = point.powerSource
        when {
            watts == null && cpu != null ->
                point.copy(powerWatts = profile.watts(cpu), powerSource = ESTIMATE_SOURCE)
            watts == null || estimate == null || source == null || PowerEstimate.covered(source) == null -> point
            else -> point.copy(
                powerWatts = watts + estimate.unseenWatts(source, watts, cpu),
                powerSource = source + COMPLETED_SUFFIX,
            )
        }
    }

    /** Kilowatt-hours of points each standing for `intervalSeconds` */
    fun kilowattHours(points: List<MetricsHistoryPoint>, intervalSeconds: Double, from: Instant, to: Instant): Double =
        points.filter { !it.date.isBefore(from) && it.date.isBefore(to) }
            .mapNotNull { it.powerWatts }
            .sumOf { it * intervalSeconds / 3_600 } / 1_000

    /** Whether any point came from a real sensor */
    fun isMeasured(points: List<MetricsHistoryPoint>): Boolean =
        points.any { it.powerWatts != null && it.powerSource != ESTIMATE_SOURCE }

    /** Mean watts of the points that carry a reading */
    fun averageWatts(points: List<MetricsHistoryPoint>): Double? =
        points.mapNotNull { it.powerWatts }.takeIf { it.isNotEmpty() }?.average()

    /** Hours of a range covered by points of `intervalSeconds` */
    fun coveredHours(points: List<MetricsHistoryPoint>, intervalSeconds: Double, from: Instant, to: Instant): Double =
        points.count { !it.date.isBefore(from) && it.date.isBefore(to) && it.powerWatts != null } *
            intervalSeconds / 3_600

    /** Known energy plus the average rate for the other hours */
    fun monthForecast(
        daily: List<MetricsHistoryPoint>,
        hourly: List<MetricsHistoryPoint>,
        now: Instant,
        zone: ZoneId,
    ): Double {
        val start = now.atZone(zone).with(TemporalAdjusters.firstDayOfMonth()).truncatedTo(ChronoUnit.DAYS)
        val monthHours = ChronoUnit.SECONDS.between(start, start.plusMonths(1)) / 3_600.0
        val from = start.toInstant()
        val today = now.atZone(zone).truncatedTo(ChronoUnit.DAYS).toInstant()
        val known = kilowattHours(daily, 86_400.0, from, today) + kilowattHours(hourly, 3_600.0, today, Instant.MAX)
        val knownHours = coveredHours(daily, 86_400.0, from, today) +
            coveredHours(hourly, 3_600.0, today, Instant.MAX)
        val average = averageWatts(hourly) ?: averageWatts(daily) ?: return known
        return known + average * maxOf(monthHours - knownHours, 0.0) / 1_000
    }
}
