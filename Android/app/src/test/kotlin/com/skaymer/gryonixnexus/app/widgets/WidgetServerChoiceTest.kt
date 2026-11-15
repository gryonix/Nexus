package com.skaymer.gryonixnexus.app.widgets

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals

class WidgetServerChoiceTest {
    private val now = 1L
    private val orion = FleetSnapshot.Server(id = "a", name = "orion", updates = FleetSnapshot.UpdatesSummary(waiting = 0, checked = 3, takenAt = now))
    private val draco = FleetSnapshot.Server(id = "b", name = "draco", updates = FleetSnapshot.UpdatesSummary(waiting = 2, checked = 4, takenAt = now))
    private val bare = FleetSnapshot.Server(id = "c", name = "bare")
    private val snapshot = FleetSnapshot(servers = listOf(orion, draco, bare))

    @Test
    fun thePickedServerIsShown() {
        assertEquals("draco", WidgetServerChoice.pick(snapshot, "b") { it.updates != null }?.name)
    }

    @Test
    fun withoutAPickTheFirstServerWithTheReadingIsShown() {
        assertEquals("orion", WidgetServerChoice.pick(snapshot, null) { it.updates != null }?.name)
    }

    @Test
    fun aPickedServerWithoutTheReadingFallsBackToTheFirst() {
        assertEquals("orion", WidgetServerChoice.pick(snapshot, "c") { it.updates != null }?.name)
    }

    @Test
    fun onlyServersWithReadingsAreOffered() {
        assertEquals(listOf("orion", "draco"), WidgetServerChoice.choices(snapshot).map { it.name })
    }
}
