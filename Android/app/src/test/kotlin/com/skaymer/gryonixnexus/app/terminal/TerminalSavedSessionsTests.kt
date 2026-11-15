package com.skaymer.gryonixnexus.app.terminal

import com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TerminalSavedSessionsTests {
    private fun record(name: String, deployment: String = "d-$name") =
        SavedTerminalSession(profileID = "p-$name", deploymentID = deployment, username = name)

    @Test
    fun openSelectsAndKeepsOrder() {
        val sessions = SavedTerminalSessions().open(record("a")).open(record("b")).open(record("a"))
        assertEquals(listOf("a", "b"), sessions.records.map { it.username })
        assertEquals("p-a", sessions.selected)
    }

    @Test
    fun closeMovesSelectionToLast() {
        val sessions = SavedTerminalSessions().open(record("a")).open(record("b")).close("p-b")
        assertEquals("a", sessions.selectedRecord?.username)
    }

    @Test
    fun closeAllForDeploymentKeepsOthers() {
        val sessions = SavedTerminalSessions()
            .open(record("a", "server")).open(record("b", "server")).open(record("c"))
            .select("p-a").closeAll("server")
        assertEquals(listOf("c"), sessions.records.map { it.username })
        assertEquals("c", sessions.selectedRecord?.username)
    }

    @Test
    fun storeRoundTripsThroughSettings() {
        val store = SavedTerminalSessionsStore(InMemorySettingsStore())
        assertTrue(store.load().records.isEmpty())
        val saved = SavedTerminalSessions().open(record("x")).open(record("y").copy(nodeID = "n1"))
        store.save(saved)
        assertEquals(saved, store.load())
    }

    @Test
    fun restorableFindsTheServersSession() {
        val sessions = SavedTerminalSessions().open(record("a", "s1")).open(record("b", "s2"))
        assertEquals("a", sessions.restorable("s1")?.username)
        assertEquals(null, sessions.restorable("s3"))
    }

    @Test
    fun tmuxCommandNamesSessionByProfile() {
        val command = TerminalTmux.launchCommand("ABCDEF12-0000")
        assertTrue(command.contains("tmux new -A -s gryonix-abcdef12"))
        assertTrue(command.endsWith("\r"))
    }
}
