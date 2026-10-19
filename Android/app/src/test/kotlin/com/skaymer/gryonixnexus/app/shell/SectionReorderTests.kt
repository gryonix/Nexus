package com.skaymer.gryonixnexus.app.shell

import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** Reordering the bar */
class SectionReorderTests {
    private fun settings() = TabBarSettings(InMemorySettingsStore())

    @Test
    fun `moving a section down swaps it with the one below`() {
        val tabs = settings()
        val before = tabs.order.value
        val moved = before[1]
        val displaced = before[2]

        tabs.moveDown(moved)

        assertEquals(displaced, tabs.order.value[1])
        assertEquals(moved, tabs.order.value[2])
        assertEquals(before.toSet(), tabs.order.value.toSet(), "a move is a reorder, not an edit")
        assertEquals(before.size, tabs.order.value.size)
    }

    @Test
    fun `moving a section up swaps it with the one above`() {
        val tabs = settings()
        val before = tabs.order.value
        val moved = before[2]
        val displaced = before[1]

        tabs.moveUp(moved)

        assertEquals(moved, tabs.order.value[1])
        assertEquals(displaced, tabs.order.value[2])
        assertEquals(
            before.drop(3), tabs.order.value.drop(3),
            "the rest of the bar stays where it was"
        )
    }

    @Test
    fun `the ends of the list do not move`() {
        val tabs = settings()
        val before = tabs.order.value

        tabs.moveUp(before.first())
        assertEquals(before, tabs.order.value)

        tabs.moveDown(before.last())
        assertEquals(before, tabs.order.value)
    }

    /** What the buttons are disabled by */
    @Test
    fun `the arrows are offered exactly where they do something`() {
        val tabs = settings()
        val order = tabs.order.value

        assertFalse(tabs.canMoveUp(order.first()))
        assertTrue(tabs.canMoveDown(order.first()))
        assertTrue(tabs.canMoveUp(order.last()))
        assertFalse(tabs.canMoveDown(order.last()))
    }

    @Test
    fun `a move is written down`() {
        val store = InMemorySettingsStore()
        val tabs = TabBarSettings(store)
        tabs.moveDown(tabs.order.value[0])
        val expected = tabs.order.value

        assertEquals(expected, TabBarSettings(store).order.value)
    }

    @Test
    fun `hiding a section is written down`() {
        val store = InMemorySettingsStore()
        val tabs = TabBarSettings(store)
        tabs.setVisible(false, AppTab.CONFIGURATOR)

        val reloaded = TabBarSettings(store)
        assertFalse(reloaded.isVisible(AppTab.CONFIGURATOR))
        assertFalse(reloaded.visibleTabs.contains(AppTab.CONFIGURATOR))
        assertTrue(reloaded.visibleTabs.contains(AppTab.SERVERS), "and only that one went")
    }

    @Test
    fun `the sections drawn are the ones both gates allow`() {
        val tabs = settings()
        val order = tabs.visibleTabs

        val withMetrics = ShellSections.visible(
            order, MetricsPlacement.BOTH.raw, VPNPlacement.BOTH.raw,
            ContainersPlacement.BOTH.raw, TerminalPlacement.BOTH.raw
        )
        val withoutMetrics = ShellSections.visible(
            order, MetricsPlacement.SERVER.raw, VPNPlacement.BOTH.raw,
            ContainersPlacement.BOTH.raw, TerminalPlacement.BOTH.raw
        )

        assertTrue(withMetrics.contains(AppTab.METRICS))
        assertFalse(
            withoutMetrics.contains(AppTab.METRICS),
            "a section that lives inside a server only is not on the bar"
        )
        assertEquals(
            withMetrics.filter { it != AppTab.METRICS }, withoutMetrics,
            "and nothing else moves out of the user's order"
        )
    }

    @Test
    fun `the sections that start inside a server are not drawn on the bar`() {
        val tabs = settings()
        val sections = ShellSections.visible(
            tabs.visibleTabs, MetricsPlacement.BOTH.raw, VPNPlacement.BOTH.raw,
            ContainersPlacement.SERVER.raw, TerminalPlacement.SERVER.raw
        )

        assertFalse(sections.contains(AppTab.CONTAINERS))
        assertFalse(sections.contains(AppTab.TERMINAL))
        assertTrue(sections.contains(AppTab.SERVERS))
        assertTrue(sections.contains(AppTab.SETTINGS), "settings can never be hidden")
    }

    @Test
    fun `reordering the bar changes what the first slot holds`() {
        val tabs = settings()
        val first = tabs.visibleTabs[0]
        val second = tabs.visibleTabs[1]

        tabs.moveUp(second)

        val sections = ShellSections.visible(
            tabs.visibleTabs, MetricsPlacement.BOTH.raw, VPNPlacement.BOTH.raw,
            ContainersPlacement.BOTH.raw, TerminalPlacement.BOTH.raw
        )
        assertEquals(second, sections.first(), "the bar follows the order, not the enum")
        assertEquals(first, sections[1])
    }

    @Test
    fun `the start section falls back only when it is gone`() {
        val tabs = settings()
        tabs.setStartTab(AppTab.CONFIGURATOR)
        assertEquals(AppTab.CONFIGURATOR, tabs.effectiveStartTab)

        tabs.setVisible(false, AppTab.CONFIGURATOR)
        assertEquals(tabs.visibleTabs.first(), tabs.effectiveStartTab)
        assertFalse(tabs.effectiveStartTab == AppTab.CONFIGURATOR)
    }

    @Test
    fun `a stored hidden set cannot hide settings`() {
        val store = InMemorySettingsStore()
        store.setStringList(TabBarSettings.Keys.HIDDEN, AppTab.entries.map { it.key })
        val tabs = TabBarSettings(store)

        assertTrue(tabs.isVisible(AppTab.SETTINGS), "settings was accepted into the hidden set")
        assertFalse(tabs.isVisible(AppTab.SERVERS), "and the rest of the file was still honoured")
        assertEquals(listOf(AppTab.SETTINGS), tabs.visibleTabs)
    }

    @Test
    fun `a file that hides only settings changes nothing`() {
        val store = InMemorySettingsStore()
        store.setStringList(TabBarSettings.Keys.HIDDEN, listOf(AppTab.SETTINGS.key))
        val tabs = TabBarSettings(store)

        assertEquals(AppTab.entries.toList(), tabs.visibleTabs)
    }
}
