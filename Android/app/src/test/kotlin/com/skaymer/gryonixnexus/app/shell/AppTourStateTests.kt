package com.skaymer.gryonixnexus.app.shell

import com.skaymer.gryonixnexus.app.ui.AppTourStep
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class AppTourStateTests {
    @Test
    fun `a fresh install has not seen the tour, and finishing remembers it`() {
        val store = InMemorySettingsStore()
        assertFalse(AppTourState(store).hasBeenShown)
        AppTourState(store).markShown()
        assertTrue(AppTourState(store).hasBeenShown)
    }

    @Test
    fun `the steps run from the demo to the finish and stop there`() {
        assertEquals(AppTourStep.DEMO, AppTourStep.entries.first())
        assertEquals(AppTourStep.SECTION_BAR, AppTourStep.DEMO.next)
        assertNull(AppTourStep.FINISH.next)
        assertNull(AppTourStep.DEMO.previous)
    }

    @Test
    fun `asking again bumps the request count`() {
        val before = AppTourRequests.count.value
        AppTourRequests.request()
        assertEquals(before + 1, AppTourRequests.count.value)
    }

    @Test
    fun `the server steps open a server page and the ends stay on the fleet`() {
        assertNull(AppTourStep.DEMO.section)
        assertNull(AppTourStep.SERVER_CARD.section)
        assertEquals(ServerSection.GENERAL, AppTourStep.SERVER_STRIP.section)
        assertEquals(ServerSection.APPS, AppTourStep.APPS.section)
        assertEquals(ServerSection.METRICS, AppTourStep.METRICS.section)
        assertEquals(ServerSection.GENERAL, AppTourStep.SECURITY.section)
        assertNull(AppTourStep.FINISH.section)
    }
}
