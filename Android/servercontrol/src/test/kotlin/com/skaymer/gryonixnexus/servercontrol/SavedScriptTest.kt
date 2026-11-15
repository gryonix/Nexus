package com.skaymer.gryonixnexus.servercontrol

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SavedScriptTest {
    @Test
    fun validityAndAvailability() {
        val everywhere = SavedScript("1", "Disk", "df -h")
        val scoped = SavedScript("2", "Logs", "journalctl -n 5", listOf("s"))
        assertTrue(everywhere.isValid)
        assertFalse(SavedScript("3", " ", "ls").isValid)
        assertFalse(SavedScript("4", "x", "\n").isValid)
        assertEquals(2, SavedScriptList.available("s", listOf(everywhere, scoped)).size)
        assertEquals(listOf(everywhere), SavedScriptList.available("t", listOf(everywhere, scoped)))
    }

    @Test
    fun terminalInputAndExecCommand() {
        val script = SavedScript("1", "q", "echo 'it''s'\nls\n\n")
        assertEquals("echo 'it''s'\nls\n", script.terminalInput)
        assertEquals("sh -c 'echo '\\''it'\\'''\\''s'\\''\nls\n\n'", script.execCommand)
    }

    @Test
    fun listEdits() {
        val one = SavedScript("1", "a", "x", listOf("s"))
        val two = SavedScript("2", "b", "y")
        var all = SavedScriptList.upserting(two, SavedScriptList.upserting(one, emptyList()))
        all = SavedScriptList.upserting(two.copy(body = "z"), all)
        assertEquals(listOf("x", "z"), all.map { it.body })
        assertEquals(emptyList(), SavedScriptList.forgettingServer("s", all)[0].deploymentIDs)
        assertEquals(listOf(all[1]), SavedScriptList.removing("1", all))
    }
}
