package com.skaymer.gryonixnexus.app.shell

import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class SitesPlateTests {
    private fun settings(store: SettingsStore = InMemorySettingsStore()) = TabBarSettings(store)

    @Test
    fun `folding is on until somebody says otherwise`() {
        assertTrue(settings().sitesCollapsible.value)
    }

    @Test
    fun `the choice survives the store, under the key the other app writes`() {
        val store = InMemorySettingsStore()
        settings(store).setSitesCollapsible(false)
        assertEquals("dashboard.sitesCollapsible", TabBarSettings.Keys.SITES_COLLAPSIBLE)
        assertEquals(false, store.boolean(TabBarSettings.Keys.SITES_COLLAPSIBLE))
        assertFalse(settings(store).sitesCollapsible.value)
    }

    /** The one that is not obvious */
    @Test
    fun `a plate that cannot be folded is never folded`() {
        val open = settings()
        assertTrue(open.sitesPlateExpanded(folded = false))
        assertFalse(open.sitesPlateExpanded(folded = true), "with folding on, a folded plate is closed")

        val store = InMemorySettingsStore()
        val flat = settings(store)
        flat.setSitesCollapsible(false)
        assertTrue(flat.sitesPlateExpanded(folded = true), "with folding off, the same plate is open")
        assertTrue(flat.sitesPlateExpanded(folded = false))
    }

    @Test
    fun `automatic grouping is an absent key, not a stored word`() {
        val store = InMemorySettingsStore()
        val tabs = settings(store)
        assertEquals(null, tabs.groupServicesOverride.value)

        tabs.setGroupServicesOverride(false)
        assertEquals(false, store.boolean(TabBarSettings.Keys.GROUP_SERVICES))
        assertEquals(false, settings(store).groupServicesOverride.value)

        tabs.setGroupServicesOverride(null)
        assertEquals(null, store.boolean(TabBarSettings.Keys.GROUP_SERVICES))
        assertEquals(null, settings(store).groupServicesOverride.value)
    }
}
