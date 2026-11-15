package com.skaymer.gryonixnexus.app.terminal

import com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class TerminalThemeTests {
    @Test
    fun everyBuiltInThemeHasSixteenValidColours() {
        assertTrue(TerminalThemes.builtIn.size >= 10)
        TerminalThemes.builtIn.forEach { assertEquals(16, it.ansi.size, it.name); assertTrue(it.isValid, it.name) }
        assertEquals(TerminalThemes.builtIn.size, TerminalThemes.builtIn.map { it.id }.toSet().size)
    }

    private fun colour(red: Double, green: Double, blue: Double) =
        "<dict><key>Red Component</key><real>$red</real><key>Green Component</key><real>$green</real>" +
            "<key>Blue Component</key><real>$blue</real></dict>"

    private fun plist(skip: String? = null): String {
        val body = (0 until 16).joinToString("") { "<key>Ansi $it Color</key>${colour(it / 15.0, 0.0, 1.0)}" } +
            "<key>Background Color</key>${colour(0.0, 0.0, 0.0)}" +
            "<key>Foreground Color</key>${colour(1.0, 1.0, 1.0)}" +
            "<key>Cursor Color</key>${colour(1.0, 0.0, 0.0)}"
        val text = skip?.let { body.replace("<key>$it</key>", "<key>X</key>") } ?: body
        return "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict>$text</dict></plist>"
    }

    @Test
    fun itermColorsParse() {
        val theme = ITermColorsImport.theme(plist(), "Test")
        assertEquals(16, theme.ansi.size)
        assertEquals("#FF00FF", theme.ansi[15])
        assertEquals("#000000", theme.background)
        assertEquals("#FF0000", theme.cursor)
        assertEquals(theme.ansi[8], theme.selection)
        assertTrue(theme.isValid)
    }

    @Test
    fun itermColorsMissingColourFails() {
        assertFailsWith<ITermColorsImport.Failure> { ITermColorsImport.theme(plist("Ansi 3 Color"), "x") }
        assertFailsWith<ITermColorsImport.Failure> { ITermColorsImport.theme("nope", "x") }
    }

    @Test
    fun serverOverrideBeatsSystemMode() {
        val look = TerminalAppearance(serverThemes = mapOf("prod" to "production-red"))
        assertEquals("production-red", look.theme(false, "prod").id)
        assertEquals(TerminalThemes.DEFAULT_LIGHT_ID, look.theme(false, null).id)
    }

    @Test
    fun appearanceRoundTripsThroughSettings() {
        val settings = InMemorySettingsStore()
        val store = TerminalAppearanceStore(settings)
        val custom = ITermColorsImport.theme(plist(), "Mine")
        store.update { it.copy(fontSize = 17.0, cursorShape = TerminalCursorShape.BAR).saving(custom) }
        val again = TerminalAppearanceStore(settings)
        assertEquals(store.look.value, again.look.value)
    }

    @Test
    fun removingCustomThemeResetsReferences() {
        val custom = ITermColorsImport.theme(plist(), "Mine")
        val look = TerminalAppearance(darkThemeID = custom.id, serverThemes = mapOf("a" to custom.id)).saving(custom)
            .removingCustom(custom.id)
        assertEquals(TerminalThemes.DEFAULT_DARK_ID, look.darkThemeID)
        assertTrue(look.serverThemes.isEmpty())
    }

    @Test
    fun zoomClamps() {
        assertEquals(32.0, TerminalAppearance().zoomed(100.0).fontSize)
        assertEquals(8.0, TerminalAppearance().zoomed(0.001).fontSize)
    }
}
