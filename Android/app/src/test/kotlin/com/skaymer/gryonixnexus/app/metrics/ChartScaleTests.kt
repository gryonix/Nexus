package com.skaymer.gryonixnexus.app.metrics

import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The value axis, and the setting that decides it */
class ChartScaleTests {
    @Test
    fun `auto until somebody says otherwise, as on the other side`() {
        assertTrue(ChartScale.auto(null))
        assertTrue(ChartScale.auto(true))
        assertEquals(false, ChartScale.auto(false))
        assertEquals("metrics.historyAutoScale", ChartScale.AUTO_KEY)
    }

    @Test
    fun `absolute means nought to a hundred for a percent chart`() {
        val quiet = ChartScale.of(listOf(2.0, 3.0, 5.0), percentChart = true, auto = false)
        assertEquals(0.0, quiet.floor)
        assertEquals(100.0, quiet.ceiling)

        val busy = ChartScale.of(listOf(91.0, 99.0), percentChart = true, auto = false)
        assertEquals(0.0, busy.floor)
        assertEquals(100.0, busy.ceiling)
    }

    @Test
    fun `absolute still fits a metric that has no hundred`() {
        val range = ChartScale.of(listOf(100.0, 400.0), percentChart = false, auto = false)
        assertEquals(0.0, range.floor)
        assertEquals(400.0 * 1.15, range.ceiling)
        assertTrue(ChartScale.of(emptyList(), percentChart = false, auto = false).span > 0)
    }

    /** The case the setting exists for */
    @Test
    fun `auto gives a quiet machine an axis it can be seen on`() {
        val values = listOf(2.0, 3.5, 5.0)
        val fitted = ChartScale.of(values, percentChart = true, auto = true)
        val absolute = ChartScale.of(values, percentChart = true, auto = false)
        assertTrue(fitted.span < absolute.span / 10, "fitted ${fitted.span} vs absolute ${absolute.span}")
        assertTrue(fitted.floor < 2.0 && fitted.ceiling > 5.0, "the data has to fit inside it")
    }

    /** The padding, number for number with `MetricsHistoryView.yDomain` */
    @Test
    fun `the band is fifteen percent of the spread on each side`() {
        val range = ChartScale.of(listOf(20.0, 40.0), percentChart = true, auto = true)
        assertEquals(20.0 - 3.0, range.floor)
        assertEquals(40.0 + 3.0, range.ceiling)
    }

    @Test
    fun `a flat line still gets an axis`() {
        val flat = ChartScale.of(listOf(40.0, 40.0, 40.0), percentChart = true, auto = true)
        assertTrue(flat.span > 0)
        assertTrue(flat.floor < 40.0 && flat.ceiling > 40.0)

        val zero = ChartScale.of(listOf(0.0, 0.0), percentChart = true, auto = true)
        assertTrue(zero.span > 0, "a machine reading zero is not a chart with no axis")
        assertEquals(0.0, zero.floor, "and it cannot start below nothing")
    }

    @Test
    fun `a percent axis stays inside nought and a hundred`() {
        val high = ChartScale.of(listOf(96.0, 100.0), percentChart = true, auto = true)
        assertTrue(high.ceiling <= 100.0, "ceiling ${high.ceiling}")
        assertTrue(high.floor >= 0.0)

        val low = ChartScale.of(listOf(0.0, 1.0), percentChart = true, auto = true)
        assertTrue(low.floor >= 0.0, "floor ${low.floor}")
        assertTrue(low.ceiling > low.floor)
    }
}
