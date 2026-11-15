package com.skaymer.gryonixnexus.app.terminal

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertSame
import kotlin.test.assertTrue

class TerminalShellsTests {
    private val shells = TerminalShells { CoroutineScope(SupervisorJob() + Dispatchers.Unconfined) }

    private fun model(scope: CoroutineScope) = TerminalViewModel(scope, sessions = { _, _ -> error("not dialled") })

    @Test
    fun severalShellsPerServerOneTabEach() {
        val (first, fresh) = shells.obtain("p1", "d1", "root", ::model)
        val (again, freshAgain) = shells.obtain("p1", "d1", "root", ::model)
        shells.obtain("p2", "d1", "admin", ::model)
        shells.obtain("p3", "d2", "root", ::model)
        assertTrue(fresh)
        assertFalse(freshAgain)
        assertSame(first, again)
        assertEquals(listOf("p1", "p2"), shells.of("d1").map { it.profileID })
        shells.close("p1")
        assertEquals(listOf("p2"), shells.of("d1").map { it.profileID })
        assertEquals(3 - 1, shells.open.value.size)
    }

    @Test
    fun restoreKeepsKnownLoginsAndTheSelectedOne() {
        val saved = SavedTerminalSessions()
            .open(SavedTerminalSession("a", "d1", username = "root"))
            .open(SavedTerminalSession("gone", "d1", username = "old"))
            .open(SavedTerminalSession("b", "d1", username = "admin"))
            .open(SavedTerminalSession("c", "d2", username = "root"))
            .select("a")
        val known = listOf(TerminalProfile("a", "root", usesAppKey = true), TerminalProfile("b", "admin", usesAppKey = true))
        val (back, shown) = TerminalRestore.plan(saved, "d1", known)
        assertEquals(listOf("a", "b"), back.map { it.id })
        assertEquals("a", shown)
        val (_, otherShown) = TerminalRestore.plan(saved.select("c"), "d1", known)
        assertEquals("b", otherShown)
    }
}
