package com.skaymer.gryonixnexus.app.notify

import com.skaymer.gryonixnexus.agentcontrol.AgentJobKind
import com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore
import com.skaymer.gryonixnexus.servercontrol.DetachedJobs
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class OperationDisplayTest {
    @Test
    fun `everything shows by default`() {
        val display = OperationDisplay()
        assertTrue(OperationKind.entries.all(display::shows))
    }

    @Test
    fun `the master switch hides every kind`() {
        val display = OperationDisplay(enabled = false)
        assertTrue(OperationKind.entries.none(display::shows))
    }

    @Test
    fun `a hidden kind is the only one left out`() {
        val display = OperationDisplay().withKind(OperationKind.BACKUP, shown = false)
        assertFalse(display.shows(OperationKind.BACKUP))
        assertTrue(display.shows(OperationKind.UPDATE))
        assertTrue(display.withKind(OperationKind.BACKUP, shown = true).shows(OperationKind.BACKUP))
    }

    @Test
    fun `choices survive a save and load`() {
        val store = InMemorySettingsStore()
        OperationDisplay(enabled = false, hidden = setOf(OperationKind.MOVE, OperationKind.OTHER)).save(store)
        val loaded = OperationDisplay.load(store)
        assertFalse(loaded.enabled)
        assertEquals(setOf(OperationKind.MOVE, OperationKind.OTHER), loaded.hidden)
    }

    @Test
    fun `an empty store means everything shows`() {
        assertEquals(OperationDisplay(), OperationDisplay.load(InMemorySettingsStore()))
    }

    @Test
    fun `agent job kinds map to operation kinds`() {
        assertEquals(OperationKind.UPDATE, OperationKind.of(AgentJobKind.CONTAINER_UPDATE))
        assertEquals(OperationKind.REMOVAL, OperationKind.of(AgentJobKind.CONTAINER_REMOVAL))
        assertEquals(OperationKind.MOVE, OperationKind.of(AgentJobKind.MOVE))
        assertEquals(OperationKind.OTHER, OperationKind.of(AgentJobKind.MODEL_PULL))
        assertEquals(OperationKind.OTHER, OperationKind.of(AgentJobKind.UNKNOWN))
    }

    @Test
    fun `detached job kinds map to operation kinds`() {
        assertEquals(OperationKind.REMOVAL, OperationKind.of(DetachedJobs.Kind.UNINSTALL))
        assertEquals(OperationKind.OTHER, OperationKind.of(DetachedJobs.Kind.CONTROL))
        assertEquals(OperationKind.RESTORE, OperationKind.of(DetachedJobs.Kind.RESTORE))
    }
}
