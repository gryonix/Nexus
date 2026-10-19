package com.skaymer.gryonixnexus.app.metrics

import com.skaymer.gryonixnexus.servercontrol.EnergyMath
import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryPoint
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters

/** Power now and energy per day and month */
data class EnergySummary(
    val latest: MetricsHistoryPoint?,
    val isMeasured: Boolean,
    val today: Double,
    val monthSoFar: Double,
    val monthForecast: Double,
    val lastMonth: Double?,
    val days: List<Pair<LocalDate, Double>>,
) {
    companion object {
        fun of(
            now: List<MetricsHistoryPoint>,
            hourly: List<MetricsHistoryPoint>,
            daily: List<MetricsHistoryPoint>,
            clock: Instant = Instant.now(),
            zone: ZoneId = ZoneId.systemDefault(),
        ): EnergySummary {
            val todayDate = clock.atZone(zone).toLocalDate()
            val startOfToday = todayDate.atStartOfDay(zone).toInstant()
            val monthStart = todayDate.with(TemporalAdjusters.firstDayOfMonth()).atStartOfDay(zone).toInstant()
            val lastMonthStart = todayDate.minusMonths(1).with(TemporalAdjusters.firstDayOfMonth()).atStartOfDay(zone).toInstant()
            val today = EnergyMath.kilowattHours(hourly, 3_600.0, startOfToday, Instant.MAX)
            val soFar = EnergyMath.kilowattHours(daily, 86_400.0, monthStart, startOfToday) + today
            val last = EnergyMath.kilowattHours(daily, 86_400.0, lastMonthStart, monthStart)
            val since = todayDate.minusDays(30).atStartOfDay(zone).toInstant()
            val past = daily.filter { !it.date.isBefore(since) && it.date.isBefore(startOfToday) }
                .mapNotNull { point -> point.powerWatts?.let { point.date.atZone(zone).toLocalDate() to it * 24 / 1_000 } }
            return EnergySummary(
                latest = now.lastOrNull { it.powerWatts != null } ?: hourly.lastOrNull { it.powerWatts != null },
                isMeasured = EnergyMath.isMeasured(now + hourly),
                today = today,
                monthSoFar = soFar,
                monthForecast = EnergyMath.monthForecast(daily, hourly, clock, zone),
                lastMonth = last.takeIf { it > 0 },
                days = past + (todayDate to today),
            )
        }
    }
}
