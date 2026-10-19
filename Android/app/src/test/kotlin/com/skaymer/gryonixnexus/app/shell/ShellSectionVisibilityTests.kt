package com.skaymer.gryonixnexus.app.shell

import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class ShellSectionVisibilityTests {
    private val store = InMemorySettingsStore()
    private val tabs = TabBarSettings(store)

    /** A plain section: nothing but the layout switch decides it */
    @Test
    fun `a plain section follows the layout switch`() {
        assertTrue(ShellSectionVisibility.isOnBar(AppTab.CONFIGURATOR, tabs, store))
        ShellSectionVisibility.setOnBar(false, AppTab.CONFIGURATOR, tabs, store)
        assertFalse(tabs.isVisible(AppTab.CONFIGURATOR))
        assertFalse(ShellSectionVisibility.isOnBar(AppTab.CONFIGURATOR, tabs, store))
        ShellSectionVisibility.setOnBar(true, AppTab.CONFIGURATOR, tabs, store)
        assertTrue(ShellSectionVisibility.isOnBar(AppTab.CONFIGURATOR, tabs, store))
    }

    @Test
    fun `the terminal is off the bar while nothing is hidden`() {
        assertTrue(tabs.isVisible(AppTab.TERMINAL), "the fixture stopped testing the placement gate")
        assertFalse(ShellSectionVisibility.isOnBar(AppTab.TERMINAL, tabs, store))
    }

    @Test
    fun `switching on a placed section moves the placement`() {
        ShellSectionVisibility.setOnBar(true, AppTab.TERMINAL, tabs, store)
        assertEquals(
            TerminalPlacement.BOTH.raw,
            store.string(DisplaySettings.TERMINAL_PLACEMENT_KEY)
        )
        assertTrue(ShellSectionVisibility.isOnBar(AppTab.TERMINAL, tabs, store))
    }

    @Test
    fun `switching off a placed section keeps it inside the server`() {
        ShellSectionVisibility.setOnBar(true, AppTab.CONTAINERS, tabs, store)
        assertTrue(ShellSectionVisibility.isOnBar(AppTab.CONTAINERS, tabs, store))

        ShellSectionVisibility.setOnBar(false, AppTab.CONTAINERS, tabs, store)
        assertEquals(
            ContainersPlacement.SERVER.raw,
            store.string(DisplaySettings.CONTAINERS_PLACEMENT_KEY)
        )
        assertFalse(ShellSectionVisibility.isOnBar(AppTab.CONTAINERS, tabs, store))
        assertTrue(
            tabs.isVisible(AppTab.CONTAINERS),
            "the section was hidden outright instead of moved inside the server"
        )
    }

    @Test
    fun `switching a placed section back on clears both gates`() {
        tabs.setVisible(false, AppTab.METRICS)
        store.setString(DisplaySettings.METRICS_PLACEMENT_KEY, MetricsPlacement.SERVER.raw)

        ShellSectionVisibility.setOnBar(true, AppTab.METRICS, tabs, store)

        assertTrue(tabs.isVisible(AppTab.METRICS))
        assertEquals(
            MetricsPlacement.BOTH.raw,
            store.string(DisplaySettings.METRICS_PLACEMENT_KEY)
        )
        assertTrue(ShellSectionVisibility.isOnBar(AppTab.METRICS, tabs, store))
    }

    @Test
    fun `metrics uses its own placement spelling`() {
        ShellSectionVisibility.setOnBar(false, AppTab.METRICS, tabs, store)
        assertEquals(
            MetricsPlacement.SERVER.raw,
            store.string(DisplaySettings.METRICS_PLACEMENT_KEY)
        )
        assertFalse(ShellSectionVisibility.isOnBar(AppTab.METRICS, tabs, store))
    }

    @Test
    fun `settings cannot be taken off the bar`() {
        ShellSectionVisibility.setOnBar(false, AppTab.SETTINGS, tabs, store)
        assertTrue(ShellSectionVisibility.isOnBar(AppTab.SETTINGS, tabs, store))
        assertTrue(tabs.isVisible(AppTab.SETTINGS))
    }
}
