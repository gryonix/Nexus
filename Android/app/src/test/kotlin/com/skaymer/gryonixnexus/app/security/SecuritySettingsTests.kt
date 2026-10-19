package com.skaymer.gryonixnexus.app.security

import com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class SecuritySettingsTests {
    private val store = InMemorySettingsStore()
    private val security = SecuritySettings(store)

    @Test
    fun `every guard is on until somebody says otherwise`() {
        GatedAction.entries.forEach { assertTrue(security.isGated(it)) }
    }

    @Test
    fun `each guard is its own answer`() {
        security.setGated(false, GatedAction.EXPORT)
        assertFalse(security.isGated(GatedAction.EXPORT))
        assertTrue(security.isGated(GatedAction.ACCESS_SCREEN))
        assertTrue(security.isGated(GatedAction.REVEAL))
    }

    @Test
    fun `a guard turned off stays off, and back on stays on`() {
        security.setGated(false, GatedAction.REVEAL)
        assertFalse(SecuritySettings(store).isGated(GatedAction.REVEAL))
        security.setGated(true, GatedAction.REVEAL)
        assertTrue(SecuritySettings(store).isGated(GatedAction.REVEAL))
    }

    @Test
    fun `the stored names are the ones the other app writes`() {
        assertEquals("security.gateAccessScreen", SecuritySettings.key(GatedAction.ACCESS_SCREEN))
        assertEquals("security.gateReveal", SecuritySettings.key(GatedAction.REVEAL))
        assertEquals("security.gateExport", SecuritySettings.key(GatedAction.EXPORT))
    }
}
