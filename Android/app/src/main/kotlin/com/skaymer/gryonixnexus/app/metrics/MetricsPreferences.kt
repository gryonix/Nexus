package com.skaymer.gryonixnexus.app.metrics

import com.skaymer.gryonixnexus.app.shell.SettingsStore

/** Which periods and which metrics the app OFFERS */
class MetricsPreferences(private val store: SettingsStore) {
    object Keys {
        const val RANGES = "metrics.offeredRanges"
        const val METRICS = "metrics.offeredMetrics"
    }

    val ranges: List<HistoryRange>
        get() = load(Keys.RANGES, HistoryRange.entries) { it.rawValue }

    val metrics: List<HistoryMetric>
        get() = load(Keys.METRICS, HistoryMetric.entries) { it.key }

    fun setRange(range: HistoryRange, offered: Boolean) =
        save(Keys.RANGES, ranges, range, offered, HistoryRange.entries) { it.rawValue }

    fun setMetric(metric: HistoryMetric, offered: Boolean) =
        save(Keys.METRICS, metrics, metric, offered, HistoryMetric.entries) { it.key }

    private fun <T> load(key: String, all: List<T>, raw: (T) -> String): List<T> {
        val stored = store.stringList(key) ?: return all
        val kept = all.filter { raw(it) in stored }
        return kept.ifEmpty { all }
    }

    private fun <T> save(
        key: String,
        current: List<T>,
        item: T,
        offered: Boolean,
        all: List<T>,
        raw: (T) -> String,
    ) {
        val next = current.toMutableSet()
        if (offered) next.add(item) else if (next.size > 1) next.remove(item)
        store.setStringList(key, all.filter { it in next }.map(raw))
    }

    companion object {
        fun resolve(range: HistoryRange, offered: List<HistoryRange>): HistoryRange =
            if (range in offered) range
            else offered.minByOrNull { candidate ->
                val a = candidate.spanSeconds.toDouble()
                val b = range.spanSeconds.toDouble()
                maxOf(a, b) / minOf(a, b)
            } ?: range

        fun resolve(metrics: Set<HistoryMetric>, offered: List<HistoryMetric>): Set<HistoryMetric> {
            val kept = metrics.filter { it in offered }.toSet()
            return kept.ifEmpty { setOfNotNull(offered.firstOrNull()) }
        }
    }
}

data class OfferedCharts(
    val ranges: List<HistoryRange>,
    val metrics: List<HistoryMetric>,
) {
    companion object {
        val everything = OfferedCharts(HistoryRange.entries, HistoryMetric.entries)

        fun of(store: SettingsStore): OfferedCharts {
            val preferences = MetricsPreferences(store)
            return OfferedCharts(preferences.ranges, preferences.metrics)
        }
    }
}
