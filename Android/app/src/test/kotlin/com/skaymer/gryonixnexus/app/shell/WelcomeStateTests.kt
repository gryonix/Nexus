package com.skaymer.gryonixnexus.app.shell

import org.junit.jupiter.api.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class WelcomeStateTests {
    @Test
    fun `a fresh install has not been welcomed`() {
        assertFalse(WelcomeState(InMemorySettingsStore()).hasBeenShown)
    }

    @Test
    fun `once marked it stays marked`() {
        val store = InMemorySettingsStore()
        WelcomeState(store).markShown()
        assertTrue(WelcomeState(store).hasBeenShown)
    }

    @Test
    fun `a stored false is not a welcome that was shown`() {
        val store = InMemorySettingsStore()
        store.setBoolean("welcome.shown", false)
        assertFalse(WelcomeState(store).hasBeenShown)
    }

    /** An unwritten flag is not a false one */
    @Test
    fun `forgetting brings the welcome back`() {
        val store = InMemorySettingsStore()
        val welcome = WelcomeState(store)
        welcome.markShown()
        assertTrue(welcome.hasBeenShown)
        welcome.forget()
        assertFalse(welcome.hasBeenShown)
    }
}
