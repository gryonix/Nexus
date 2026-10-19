package com.skaymer.gryonixnexus.app.shell

import android.os.Build
import android.view.HapticFeedbackConstants
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class HapticsTests {
    /** On by default, and off is a real answer */
    @Test
    fun `feedback plays until somebody turns it off`() {
        val store = InMemorySettingsStore()
        assertTrue(store.hapticsEnabled())
        store.setHapticsEnabled(false)
        assertFalse(store.hapticsEnabled())
        store.setHapticsEnabled(true)
        assertTrue(store.hapticsEnabled())
    }

    @Test
    fun `the key is the one the other app writes`() {
        assertEquals("haptics.enabled", Haptics.KEY)
    }

    @Test
    fun `a button that destroys something is heavier than one that does not`() {
        val tap = Haptics.constant(Haptics.Feel.TAP, sdk = Build.VERSION_CODES.TIRAMISU)
        val weighty = Haptics.constant(Haptics.Feel.WEIGHTY, sdk = Build.VERSION_CODES.TIRAMISU)
        assertEquals(HapticFeedbackConstants.VIRTUAL_KEY, tap)
        assertEquals(HapticFeedbackConstants.LONG_PRESS, weighty)
    }

    @Test
    fun `an outcome still answers on a device too old for its own constant`() {
        assertEquals(
            HapticFeedbackConstants.CONFIRM,
            Haptics.constant(Haptics.Feel.SUCCESS, sdk = Build.VERSION_CODES.R),
        )
        assertEquals(
            HapticFeedbackConstants.REJECT,
            Haptics.constant(Haptics.Feel.FAILURE, sdk = Build.VERSION_CODES.R),
        )
        assertEquals(
            HapticFeedbackConstants.VIRTUAL_KEY,
            Haptics.constant(Haptics.Feel.SUCCESS, sdk = Build.VERSION_CODES.O),
        )
        assertEquals(
            HapticFeedbackConstants.LONG_PRESS,
            Haptics.constant(Haptics.Feel.FAILURE, sdk = Build.VERSION_CODES.O),
        )
    }

    @Test
    fun `every feel maps to a constant on the oldest device supported`() {
        assertEquals(4, Haptics.Feel.entries.size)
        for (feel in Haptics.Feel.entries) {
            Haptics.constant(feel, sdk = Build.VERSION_CODES.O)
        }
    }
}
