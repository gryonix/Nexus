package com.skaymer.gryonixnexus.app.metrics

import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.MetricsFormat
import kotlin.math.roundToInt

/** The line under a panel's title: averages, peaks, totals */
object MetricPanelSummary {
    fun text(
        metrics: List<HistoryMetric>,
        series: List<HistorySeries>,
        interval: Double,
        words: (Int) -> String,
    ): String {
        if (metrics.size <= 1) return line(metrics.firstOrNull() ?: HistoryMetric.CPU, series, interval, words)
        return metrics.joinToString("  ·  ") { "${words(it.titleRes)} ${line(it, series, interval, words)}" }
    }

    fun line(metric: HistoryMetric, series: List<HistorySeries>, interval: Double, words: (Int) -> String): String {
        fun values(key: String) = series.firstOrNull { it.key == key }?.values?.map { it.value }.orEmpty()
        fun total(key: String) = (values(key).sum() * interval).toLong()
        return when (metric) {
            HistoryMetric.NETWORK -> pair(words(R.string.history_series_received), total("rx"), words(R.string.history_series_sent), total("tx"))
            HistoryMetric.DISK_IO -> pair(words(R.string.metrics_disk_read), total("read"), words(R.string.metrics_disk_write), total("write"))
            HistoryMetric.CPU -> plain(values("cpu"), words) { "${it.roundToInt()} %" }
            HistoryMetric.MEMORY -> plain(values("mem"), words) { "${it.roundToInt()} %" }
            HistoryMetric.DISK -> plain(values("disk"), words) { "${it.roundToInt()} %" }
            HistoryMetric.LOAD -> plain(values("load"), words) { String.format(java.util.Locale.ROOT, "%.2f", it) }
            HistoryMetric.TEMPERATURE -> plain(values("temp"), words) { MetricsFormat.temperature(it) }
            HistoryMetric.POWER -> plain(values("power"), words) { "${it.roundToInt()} W" }
        }
    }

    private fun pair(firstName: String, first: Long, secondName: String, second: Long): String =
        "$firstName ${MetricsFormat.bytes(first)} · $secondName ${MetricsFormat.bytes(second)}"

    /** "avg 12 % · peak 61 %" */
    private fun plain(values: List<Double>, words: (Int) -> String, format: (Double) -> String): String {
        if (values.isEmpty()) return "—"
        val average = values.average()
        return "${words(R.string.metrics_avg)} ${format(average)} · ${words(R.string.metrics_peak)} ${format(values.max())}"
    }
}
