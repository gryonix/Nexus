package com.skaymer.gryonixnexus.app.shell

import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The sections across the top of ONE server's screen */
class ServerSectionSettingsTests {
    private fun settings() = ServerSectionSettings(InMemorySettingsStore())

    private val all = ServerSection.entries.toList()

    @Test
    fun `hiding belongs to one server`() {
        val settings = settings()
        settings.setVisible(false, ServerSection.CONTAINERS, "mail-only", all)

        assertFalse(settings.isVisible(ServerSection.CONTAINERS, "mail-only"))
        assertTrue(settings.isVisible(ServerSection.CONTAINERS, "the-other-one"))
        assertEquals(
            listOf(ServerSection.GENERAL, ServerSection.APPS),
            settings.ordered(listOf(ServerSection.GENERAL, ServerSection.APPS, ServerSection.CONTAINERS), "mail-only"),
        )
    }

    @Test
    fun `showing it again restores it`() {
        val settings = settings()
        settings.setVisible(false, ServerSection.VPN, "s", all)
        settings.setVisible(true, ServerSection.VPN, "s", all)
        assertTrue(settings.isVisible(ServerSection.VPN, "s"))
    }

    /** The last visible section cannot go */
    @Test
    fun `the last section standing cannot be hidden`() {
        val settings = settings()
        val two = listOf(ServerSection.GENERAL, ServerSection.APPS)
        settings.setVisible(false, ServerSection.APPS, "s", two)

        assertFalse(settings.canHide(ServerSection.GENERAL, "s", two))
        settings.setVisible(false, ServerSection.GENERAL, "s", two)
        assertTrue(settings.isVisible(ServerSection.GENERAL, "s"), "the refusal has to hold in the setter too")
    }

    @Test
    fun `forgetting a server drops its hidden sections`() {
        val settings = settings()
        settings.setVisible(false, ServerSection.METRICS, "gone", all)
        settings.forget("gone")
        assertTrue(settings.isVisible(ServerSection.METRICS, "gone"))
    }

    @Test
    fun `hidden sections are stored`() {
        val store = InMemorySettingsStore()
        ServerSectionSettings(store).setVisible(false, ServerSection.TERMINAL, "s", all)
        assertFalse(ServerSectionSettings(store).isVisible(ServerSection.TERMINAL, "s"))
    }

    @Test
    fun `a new section is reconciled into its designed place`() {
        val order = ServerSectionSettings.reconcile(listOf("general", "hosts", "operations"))
        assertEquals(ServerSection.entries.toSet(), order.toSet(), "nothing is dropped or invented")
        assertTrue(
            order.indexOf(ServerSection.GENERAL) < order.indexOf(ServerSection.METRICS),
            "the arrangement the person made is kept: ${'$'}order",
        )
        assertTrue(
            order.indexOf(ServerSection.CONTAINERS) < order.indexOf(ServerSection.APPS),
            "Containers belongs after Metrics, not at the end: ${'$'}order",
        )
        assertTrue(
            order.indexOf(ServerSection.VPN) < order.indexOf(ServerSection.APPS),
            "and so does VPN: ${'$'}order",
        )
    }

    @Test
    fun `no stored order means the designed one`() {
        assertEquals(ServerSection.entries.toList(), ServerSectionSettings.reconcile(emptyList()))
        assertEquals(ServerSection.entries.toList(), ServerSectionSettings.reconcile(listOf("nonsense")))
    }

    @Test
    fun `the start section falls back to what the server has`() {
        val settings = settings()
        settings.setStartSection(ServerSection.VPN)
        assertEquals(ServerSection.VPN, settings.startSection(all, "s"))
        assertEquals(
            ServerSection.GENERAL,
            settings.startSection(listOf(ServerSection.GENERAL, ServerSection.APPS), "s"),
        )
    }

    // ------------------------------------------------- What a server offers

    @Test
    fun `the vpn section follows the server, not the app's reach`() {
        val withVPN = ServerSectionSettings.available(
            MetricsPlacement.BOTH, ContainersPlacement.SERVER, VPNPlacement.BOTH,
            canListContainers = false, hasVPN = true,
        )
        assertTrue(ServerSection.VPN in withVPN)
        val without = ServerSectionSettings.available(
            MetricsPlacement.BOTH, ContainersPlacement.SERVER, VPNPlacement.BOTH,
            canListContainers = false, hasVPN = false,
        )
        assertFalse(ServerSection.VPN in without)
    }

    /** A placement that puts a section in the tab alone takes it off the strip. */
    @Test
    fun `a section placed in the tab is not on the strip`() {
        val sections = ServerSectionSettings.available(
            MetricsPlacement.DASHBOARD, ContainersPlacement.SECTION, VPNPlacement.TAB,
            canListContainers = true, hasVPN = true,
        )
        assertFalse(ServerSection.METRICS in sections)
        assertFalse(ServerSection.CONTAINERS in sections)
        assertFalse(ServerSection.VPN in sections)
        // What a server IS does not move, and the terminal carries the file
        // browser — gating it on the shell's placement would take the files.
        assertEquals(
            listOf(ServerSection.GENERAL, ServerSection.APPS, ServerSection.TERMINAL),
            sections,
        )
    }
    @Test
    fun `the section a screen sits on survives everything but its own disappearance`() {
        val settings = settings()
        val available = listOf(
            ServerSection.GENERAL,
            ServerSection.APPS,
            ServerSection.CONTAINERS,
        )
        assertEquals(
            ServerSection.CONTAINERS,
            settings.reachable(ServerSection.CONTAINERS, available, "a"),
        )
        settings.setVisible(false, ServerSection.CONTAINERS, "a", available)
        val landed = settings.reachable(ServerSection.CONTAINERS, available, "a")
        assertTrue(landed != ServerSection.CONTAINERS)
        assertEquals(settings.ordered(available, "a").first(), landed)
        assertEquals(
            ServerSection.CONTAINERS,
            settings.reachable(ServerSection.CONTAINERS, available, "b"),
        )
    }

    @Test
    fun `a section this server never offered cannot be the one shown`() {
        val settings = settings()
        val available = listOf(ServerSection.GENERAL, ServerSection.APPS)
        assertEquals(
            ServerSection.GENERAL,
            settings.reachable(ServerSection.VPN, available, "a"),
        )
    }
}
