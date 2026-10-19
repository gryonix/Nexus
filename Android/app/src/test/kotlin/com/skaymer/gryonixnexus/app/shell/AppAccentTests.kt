package com.skaymer.gryonixnexus.app.shell

import com.skaymer.gryonixnexus.app.ui.design.DarkColors
import com.skaymer.gryonixnexus.app.ui.design.LightColors
import com.skaymer.gryonixnexus.app.ui.design.colour
import com.skaymer.gryonixnexus.app.ui.design.withAccent
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class AppAccentTests {
    @Test
    fun `an unset accent is the app's own`() {
        val store = InMemorySettingsStore()
        assertEquals(AppAccent.APP, store.appAccent())
        assertEquals(LightColors.accent, AppAccent.APP.colour(LightColors))
        assertEquals(DarkColors.accent, AppAccent.APP.colour(DarkColors))
    }

    @Test
    fun `the key and the stored spellings are the ones the other app writes`() {
        assertEquals("appearance.accentChoice", AppAccent.KEY)
        assertEquals(AppAccent.INDIGO, AppAccent.of("indigo"))
        assertEquals(AppAccent.GRAPHITE, AppAccent.of("graphite"))
    }

    /**
     * **`matchesIcon` is a real word on the other side and has no answer
     * here**, because alternate app icons are a platform API that was
     * deliberately not ported. It has to land on the default like any other
     * unknown word — not on whichever entry happens to be declared first, and
     * not on a colour invented to stand in for it.
     */
    @Test
    fun `an answer this build has no icon for falls back to the app accent`() {
        assertEquals(AppAccent.APP, AppAccent.of("matchesIcon"))
        assertEquals(AppAccent.APP, AppAccent.of("chartreuse"))
        assertEquals(AppAccent.APP, AppAccent.of(null))
    }

    @Test
    fun `a chosen accent survives the store and bumps the revision`() {
        val store = InMemorySettingsStore()
        val before = store.revision.value
        store.setAppAccent(AppAccent.BROWN)
        assertEquals("brown", store.string(AppAccent.KEY))
        assertEquals(AppAccent.BROWN, store.appAccent())
        assertTrue(store.revision.value > before)
    }

    /**
     * **Black is ink, not a literal.** A literal black accent paints switch
     * knobs and button fills on a page that is itself black in dark mode, so
     * every one of those controls disappears into it. The assertion states
     * BOTH answers side by side: one alone would also pass on a mapping that
     * returned a constant.
     */
    @Test
    fun `black is the ink of the theme in force`() {
        assertEquals(LightColors.label, AppAccent.BLACK.colour(LightColors))
        assertEquals(DarkColors.label, AppAccent.BLACK.colour(DarkColors))
        assertNotEquals(AppAccent.BLACK.colour(LightColors), AppAccent.BLACK.colour(DarkColors))
    }

    /**
     * The named colours follow the palette the way the rest of it does — the
     * dark variants are the brighter ones Apple publishes — except graphite,
     * which is the one system colour Apple does not split.
     */
    @Test
    fun `the named colours split light and dark, and graphite does not`() {
        val split = listOf(AppAccent.RED, AppAccent.ORANGE, AppAccent.YELLOW, AppAccent.GREEN,
                           AppAccent.TEAL, AppAccent.PURPLE, AppAccent.PINK, AppAccent.INDIGO,
                           AppAccent.BROWN)
        for (accent in split) {
            assertNotEquals(
                accent.colour(LightColors), accent.colour(DarkColors),
                "$accent is the same colour in both themes",
            )
        }
        assertEquals(AppAccent.GRAPHITE.colour(LightColors), AppAccent.GRAPHITE.colour(DarkColors))
    }

    /**
     * The one thing that makes any of it visible: the palette handed to the
     * theme carries the chosen colour, and carries NOTHING ELSE from the
     * choice — a picker that also moved the page or the danger red would be a
     * theme switcher wearing a colour picker's name.
     */
    @Test
    fun `choosing an accent changes the accent and nothing else`() {
        val tinted = LightColors.withAccent(AppAccent.PURPLE)
        assertEquals(AppAccent.PURPLE.colour(LightColors), tinted.accent)
        assertEquals(LightColors, tinted.copy(accent = LightColors.accent))
    }

    @Test
    fun `every accent has a colour in both themes`() {
        assertEquals(12, AppAccent.entries.size)
        for (accent in AppAccent.entries) {
            assertNotEquals(0f, accent.colour(LightColors).alpha, "$accent is invisible on light")
            assertNotEquals(0f, accent.colour(DarkColors).alpha, "$accent is invisible on dark")
        }
    }
}
