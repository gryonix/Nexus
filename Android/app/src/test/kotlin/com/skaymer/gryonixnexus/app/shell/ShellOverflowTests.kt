package com.skaymer.gryonixnexus.app.shell

import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** What fits on the bar, and what goes behind "More" */
class ShellOverflowTests {
    private val sevenSections = AppTab.entries.toList()

    @Test
    fun `a bar that fits keeps everything and offers no more slot`() {
        val visible = sevenSections.take(5)
        assertEquals(visible, ShellSections.onBar(visible, capacity = 5))
        assertTrue(ShellSections.behindMore(visible, capacity = 5).isEmpty())
    }

    @Test
    fun `an overflowing bar spends its last slot on more`() {
        val onBar = ShellSections.onBar(sevenSections, capacity = 5)
        val behind = ShellSections.behindMore(sevenSections, capacity = 5)

        assertEquals(4, onBar.size, "four sections and the More slot make five")
        assertEquals(sevenSections, onBar + behind, "nothing is dropped and nothing is reordered")
        assertEquals(listOf(AppTab.TERMINAL, AppTab.CONFIGURATOR, AppTab.SETTINGS), behind)
    }

    @Test
    fun `the boundary is at the capacity itself`() {
        val five = sevenSections.take(5)
        val six = sevenSections.take(6)

        assertEquals(5, ShellSections.onBar(five, capacity = 5).size)
        assertEquals(4, ShellSections.onBar(six, capacity = 5).size)
        assertEquals(2, ShellSections.behindMore(six, capacity = 5).size)
    }

    @Test
    fun `a tablet draws every section`() {
        val capacity = ShellSections.barCapacity(isTablet = true)
        assertEquals(sevenSections, ShellSections.onBar(sevenSections, capacity))
        assertTrue(ShellSections.behindMore(sevenSections, capacity).isEmpty())
    }

    @Test
    fun `a phone has five slots`() {
        assertEquals(5, ShellSections.barCapacity(isTablet = false))
    }

    @Test
    fun `the shipped defaults fill the bar exactly`() {
        val tabs = TabBarSettings(InMemorySettingsStore())
        val visible = ShellSections.visible(
            tabs.visibleTabs,
            metricsRaw = null, vpnRaw = null, containersRaw = null, terminalRaw = null
        )
        assertEquals(
            listOf(
                AppTab.SERVERS, AppTab.METRICS, AppTab.VPN,
                AppTab.CONFIGURATOR, AppTab.SETTINGS
            ),
            visible
        )
        assertTrue(ShellSections.behindMore(visible, capacity = 5).isEmpty())
    }
}
