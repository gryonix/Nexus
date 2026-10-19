package com.skaymer.gryonixnexus.app.metrics

import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryBucket
import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryPoint
import java.time.Instant

enum class HistoryRange(val rawValue: String, val spanSeconds: Long) {
    TEN_MINUTES("10m", 600),
    THIRTY_MINUTES("30m", 1_800),
    HOUR("1h", 3_600),
    THREE_HOURS("3h", 3 * 3_600),
    FIVE_HOURS("5h", 5 * 3_600),
    TEN_HOURS("10h", 10 * 3_600),
    DAY("1d", 86_400),
    WEEK("1w", 7 * 86_400),
    TWELVE_DAYS("12d", 12 * 86_400),
    MONTH("1mo", 30 * 86_400),
    SIX_MONTHS("6mo", 182 * 86_400),
    YEAR("1y", 365 * 86_400);

    val bucket: MetricsHistoryBucket
        get() = when (this) {
            TEN_MINUTES, THIRTY_MINUTES -> MetricsHistoryBucket.TEN_SECONDS
            HOUR, THREE_HOURS, FIVE_HOURS -> MetricsHistoryBucket.ONE_MINUTE
            TEN_HOURS, DAY -> MetricsHistoryBucket.TEN_MINUTES
            WEEK, TWELVE_DAYS -> MetricsHistoryBucket.ONE_HOUR
            MONTH, SIX_MONTHS -> MetricsHistoryBucket.ONE_DAY
            YEAR -> MetricsHistoryBucket.ONE_WEEK
        }

    val refreshSeconds: Long
        get() = (bucket.pointInterval / 4).toLong().coerceIn(15, 60)

    companion object {
        fun of(raw: String?): HistoryRange? = entries.firstOrNull { it.rawValue == raw }
    }
}

fun List<MetricsHistoryPoint>.windowed(range: HistoryRange): List<MetricsHistoryPoint> {
    val newest = lastOrNull()?.date ?: return this
    val start: Instant = newest.minusSeconds(range.spanSeconds)
    return filter { !it.date.isBefore(start) }
}
