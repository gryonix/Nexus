package com.skaymer.gryonixnexus.app.metrics

import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.MetricsFormat
import com.skaymer.gryonixnexus.servercontrol.DiskLine
import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryPoint
import java.time.Instant

data class HistorySeries(
    val key: String,
    val nameRes: Int,
    val values: List<Sample>,
    /** Shown instead of the resource name */
    val label: String? = null,
) {
    data class Sample(val date: Instant, val value: Double)
}

/** What the chart is drawing */
enum class HistoryMetric(val key: String, val titleRes: Int) {
    CPU("cpu", R.string.metric_cpu),
    MEMORY("memory", R.string.metric_memory),
    DISK("disk", R.string.metric_disk),
    NETWORK("network", R.string.metric_network),
    DISK_IO("diskIO", R.string.metric_disk_io),
    LOAD("load", R.string.metric_load),
    TEMPERATURE("temperature", R.string.metric_temperature),
    POWER("power", R.string.metric_power);

    val isPercent: Boolean get() = this == CPU || this == MEMORY || this == DISK

    val isTwoSeries: Boolean get() = this == NETWORK || this == DISK_IO

    companion object {
        fun toggling(metric: HistoryMetric, selection: Set<HistoryMetric>): Set<HistoryMetric> {
            if (!metric.isPercent) return setOf(metric)
            val next = selection.filter { it.isPercent }.toMutableSet()
            if (!next.remove(metric)) next.add(metric)
            return next.ifEmpty { setOf(metric) }
        }

        fun series(
            metrics: Set<HistoryMetric>,
            points: List<MetricsHistoryPoint>,
            diskLines: List<DiskLine> = emptyList(),
        ): List<HistorySeries> {
            fun samples(read: (MetricsHistoryPoint) -> Double?): List<HistorySeries.Sample> =
                points.mapNotNull { point -> read(point)?.let { HistorySeries.Sample(point.date, it) } }

            val out = mutableListOf<HistorySeries>()
            for (metric in entries.filter { it in metrics }) {
                when (metric) {
                    CPU -> out += HistorySeries("cpu", R.string.metric_cpu, samples { it.cpuPercent })
                    MEMORY -> out += HistorySeries("mem", R.string.metric_memory, samples { it.memUsedFraction * 100 })
                    DISK -> out += if (diskLines.isEmpty()) {
                        listOf(HistorySeries("disk", R.string.metric_disk, samples { it.diskUsedFraction * 100 }))
                    } else {
                        diskSeries(diskLines, points.firstOrNull()?.date ?: Instant.MIN)
                    }
                    NETWORK -> {
                        out += HistorySeries("rx", R.string.history_series_received, samples { it.netReceivedPerSecond })
                        out += HistorySeries("tx", R.string.history_series_sent, samples { it.netSentPerSecond })
                    }
                    DISK_IO -> {
                        out += HistorySeries("read", R.string.metrics_disk_read, samples { it.diskReadPerSecond })
                        out += HistorySeries("write", R.string.metrics_disk_write, samples { it.diskWrittenPerSecond })
                    }
                    LOAD -> out += HistorySeries("load", R.string.metric_load, samples { it.load1 })
                    TEMPERATURE -> out += HistorySeries("temp", R.string.metric_temperature, samples { it.temperatureCelsius })
                    POWER -> out += HistorySeries("power", R.string.metric_power, samples { it.powerWatts })
                }
            }
            return out
        }

        private fun diskSeries(lines: List<DiskLine>, start: Instant): List<HistorySeries> = lines.map { line ->
            HistorySeries(
                key = "disk-${line.name}",
                nameRes = R.string.metric_disk,
                values = line.values.filter { !it.first.isBefore(start) }.map { HistorySeries.Sample(it.first, it.second) },
                label = line.name.ifEmpty { null },
            )
        }

        fun isPercentChart(metrics: Set<HistoryMetric>): Boolean = metrics.all { it.isPercent }

        /** What the chart's top of scale SAYS */
        fun axisLabel(metrics: Set<HistoryMetric>, ceiling: Double): String = when {
            isPercentChart(metrics) -> "0 – 100 %"
            metrics.all { it == NETWORK || it == DISK_IO } -> "0 – ${MetricsFormat.rate(ceiling)}"
            metrics.all { it == TEMPERATURE } -> "0 – ${MetricsFormat.temperature(ceiling)}"
            metrics.all { it == POWER } -> "0 – ${ceiling.toInt()} W"
            else -> "0 – ${MetricsFormat.load(ceiling)}"
        }
    }
}
