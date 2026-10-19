package com.skaymer.gryonixnexus.app.shell

import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class SectionPlacementTests {
    /** The bar somebody who has never touched it gets */
    @Test
    fun `the default order is the one the owner asked for`() {
        assertEquals(
            listOf(
                AppTab.SERVERS, AppTab.METRICS, AppTab.CONTAINERS, AppTab.VPN,
                AppTab.TERMINAL, AppTab.CONFIGURATOR, AppTab.SETTINGS
            ),
            TabBarSettings(InMemorySettingsStore()).order.value,
            "containers rides beside metrics, and both it and terminal are kept off " +
                "the bar by their placement, not by their position"
        )
    }

    @Test
    fun `an untouched old order is brought forward wholesale`() {
        val store = InMemorySettingsStore()
        store.setStringList(
            TabBarSettings.Keys.ORDER,
            listOf("servers", "metrics", "configurator", "vpn", "settings")
        )
        assertEquals(AppTab.entries.toList(), TabBarSettings(store).order.value)
    }

    @Test
    fun `an arranged order is added to rather than overwritten`() {
        val store = InMemorySettingsStore()
        store.setStringList(
            TabBarSettings.Keys.ORDER,
            listOf("settings", "servers", "metrics", "vpn", "configurator")
        )
        val order = TabBarSettings(store).order.value

        assertEquals(AppTab.SETTINGS, order.first(), "their arrangement survives")
        assertTrue(order.contains(AppTab.CONTAINERS))
        assertEquals(AppTab.entries.size, order.size)
        assertEquals(
            order.indexOf(AppTab.METRICS) + 1, order.indexOf(AppTab.CONTAINERS),
            "the new section sits where it was designed to go, not at the end"
        )
        assertEquals(
            order.indexOf(AppTab.VPN) + 1, order.indexOf(AppTab.TERMINAL),
            "and so does the second one that this build added"
        )
    }

    @Test
    fun `an order equal to the current default is left as it is`() {
        val store = InMemorySettingsStore()
        store.setStringList(TabBarSettings.Keys.ORDER, AppTab.entries.map { it.key })
        assertEquals(AppTab.entries.toList(), TabBarSettings(store).order.value)
    }

    @Test
    fun `containers start inside the server and not on the bar`() {
        val placement = DisplaySettings.containers(null)
        assertEquals(ContainersPlacement.SERVER, placement)
        assertFalse(placement.showsTab, "the tab is off until somebody turns it on")
        assertTrue(placement.showsInsideServer)
    }

    @Test
    fun `the terminal starts inside the server too`() {
        assertEquals(TerminalPlacement.SERVER, DisplaySettings.terminal(null))
        assertFalse(DisplaySettings.terminal(null).showsTab)
    }

    @Test
    fun `either place or both can be chosen`() {
        assertTrue(ContainersPlacement.SECTION.showsTab)
        assertFalse(ContainersPlacement.SECTION.showsInsideServer)
        assertTrue(ContainersPlacement.BOTH.showsTab)
        assertTrue(ContainersPlacement.BOTH.showsInsideServer)
    }

    /** Metrics and VPN keep THEIR default: both */
    @Test
    fun `metrics and vpn still default to both`() {
        assertEquals(MetricsPlacement.BOTH, DisplaySettings.metrics(null))
        assertEquals(VPNPlacement.BOTH, DisplaySettings.vpn(null))
    }

    @Test
    fun `the placement spellings are the ones already stored on devices`() {
        assertEquals(MetricsPlacement.DASHBOARD, DisplaySettings.metrics("dashboard"))
        assertEquals(VPNPlacement.TAB, DisplaySettings.vpn("tab"))
        assertEquals(ContainersPlacement.SECTION, DisplaySettings.containers("section"))
        assertEquals(TerminalPlacement.TAB, DisplaySettings.terminal("tab"))
        assertEquals(
            MetricsPlacement.BOTH, DisplaySettings.metrics("tab"),
            "metrics has no 'tab' case — an unknown value falls back, it does not match"
        )
    }
}
