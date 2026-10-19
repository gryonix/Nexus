package com.skaymer.gryonixnexus.app.metrics

import com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class MetricsPreferencesTests {
    /** A settings screen must not change anything by existing */
    @Test
    fun `everything is offered until somebody says otherwise`() {
        val preferences = MetricsPreferences(InMemorySettingsStore())
        assertEquals(HistoryRange.entries, preferences.ranges)
        assertEquals(HistoryMetric.entries, preferences.metrics)
    }

    @Test
    fun `the offer comes back in catalogue order, whatever order it was stored in`() {
        val store = InMemorySettingsStore()
        store.setStringList(
            MetricsPreferences.Keys.RANGES,
            listOf(HistoryRange.DAY.rawValue, HistoryRange.TEN_MINUTES.rawValue),
        )
        assertEquals(
            listOf(HistoryRange.TEN_MINUTES, HistoryRange.DAY),
            MetricsPreferences(store).ranges,
        )
    }

    /** The last one cannot be removed */
    @Test
    fun `the last standing choice stays`() {
        val preferences = MetricsPreferences(InMemorySettingsStore())
        HistoryRange.entries.forEach { preferences.setRange(it, offered = false) }
        assertEquals(1, preferences.ranges.size)

        HistoryMetric.entries.forEach { preferences.setMetric(it, offered = false) }
        assertEquals(1, preferences.metrics.size)
    }

    @Test
    fun `a stored list from another build falls back to everything`() {
        val store = InMemorySettingsStore()
        store.setStringList(MetricsPreferences.Keys.RANGES, listOf("2y", "decade"))
        assertEquals(HistoryRange.entries, MetricsPreferences(store).ranges)
    }

    /** The NEAREST still offered, not the first */
    @Test
    fun `a period that is gone falls to the nearest one still on offer`() {
        val offered = listOf(HistoryRange.TEN_MINUTES, HistoryRange.WEEK)
        assertEquals(HistoryRange.WEEK, MetricsPreferences.resolve(HistoryRange.DAY, offered))
        assertEquals(HistoryRange.TEN_MINUTES, MetricsPreferences.resolve(HistoryRange.HOUR, offered))
        // One still on offer is left exactly where it is.
        assertEquals(HistoryRange.WEEK, MetricsPreferences.resolve(HistoryRange.WEEK, offered))
    }

    @Test
    fun `metrics keep what is still offered and fall to the first when nothing is`() {
        val offered = listOf(HistoryMetric.CPU, HistoryMetric.MEMORY)
        assertEquals(
            setOf(HistoryMetric.CPU),
            MetricsPreferences.resolve(setOf(HistoryMetric.CPU, HistoryMetric.LOAD), offered),
        )
        assertEquals(
            setOf(HistoryMetric.CPU),
            MetricsPreferences.resolve(setOf(HistoryMetric.LOAD), offered),
        )
    }
}
