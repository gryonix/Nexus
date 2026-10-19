package com.skaymer.gryonixnexus.app.metrics

data class ChartRange(val floor: Double, val ceiling: Double) {
    val span: Double get() = ceiling - floor
}

object ChartScale {
    /** The same key the other app writes */
    const val AUTO_KEY = "metrics.historyAutoScale"

    /** Auto until somebody says otherwise, as on the other side */
    fun auto(stored: Boolean?): Boolean = stored ?: true

    fun of(values: List<Double>, percentChart: Boolean, auto: Boolean): ChartRange {
        if (!auto) {
            if (percentChart) return ChartRange(0.0, 100.0)
            return ChartRange(0.0, maxOf((values.maxOrNull() ?: 1.0) * 1.15, 1.0))
        }
        val low = values.minOrNull() ?: 0.0
        val high = values.maxOrNull() ?: 1.0
        var pad = (high - low) * 0.15
        if (pad <= 0) pad = maxOf(high * 0.1, if (percentChart) 2.0 else 1.0)
        var floor = maxOf(0.0, low - pad)
        var ceiling = high + pad
        if (percentChart) {
            ceiling = minOf(100.0, maxOf(ceiling, floor + 1))
            if (ceiling <= floor) floor = maxOf(0.0, ceiling - 1)
        }
        // Never a zero span: the plot divides by it.
        return ChartRange(floor, maxOf(ceiling, floor + 0.001))
    }
}
