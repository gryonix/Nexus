package com.skaymer.gryonixnexus.app.terminal

import com.skaymer.gryonixnexus.app.shell.SettingsStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

enum class TerminalCursorShape { BLOCK, BAR, UNDERLINE }

@Serializable
data class SerializableTheme(
    val id: String,
    val name: String,
    val background: String,
    val foreground: String,
    val cursor: String,
    val selection: String,
    val ansi: List<String>,
) {
    fun toTheme() = TerminalTheme(id, name, background, foreground, cursor, selection, ansi)
}

private fun TerminalTheme.serializable() = SerializableTheme(id, name, background, foreground, cursor, selection, ansi)

/** How terminals look: themes, font, cursor and backdrop */
@Serializable
data class TerminalAppearance(
    val followSystem: Boolean = true,
    val darkThemeID: String = TerminalThemes.DEFAULT_DARK_ID,
    val lightThemeID: String = TerminalThemes.DEFAULT_LIGHT_ID,
    val fixedThemeID: String = TerminalThemes.DEFAULT_DARK_ID,
    val fontName: String? = null,
    val fontSize: Double = 13.0,
    val cursorShape: TerminalCursorShape = TerminalCursorShape.BLOCK,
    val cursorBlink: Boolean = true,
    val opacity: Double = 1.0,
    val customThemes: List<SerializableTheme> = emptyList(),
    val serverThemes: Map<String, String> = emptyMap(),
) {
    val custom: List<TerminalTheme> get() = customThemes.map { it.toTheme() }
    val allThemes: List<TerminalTheme> get() = TerminalThemes.builtIn + custom

    /** The theme for a server, or the system mode. */
    fun theme(isDark: Boolean, server: String?): TerminalTheme {
        val id = server?.let { serverThemes[it] }
            ?: if (followSystem) (if (isDark) darkThemeID else lightThemeID) else fixedThemeID
        return TerminalThemes.find(id, custom)
            ?: TerminalThemes.find(if (isDark) TerminalThemes.DEFAULT_DARK_ID else TerminalThemes.DEFAULT_LIGHT_ID)!!
    }

    fun saving(theme: TerminalTheme): TerminalAppearance {
        val kept = customThemes.filter { it.id != theme.id }
        val at = customThemes.indexOfFirst { it.id == theme.id }.takeIf { it >= 0 } ?: kept.size
        return copy(customThemes = kept.toMutableList().apply { add(at, theme.serializable()) })
    }

    fun removingCustom(id: String) = copy(
        customThemes = customThemes.filter { it.id != id },
        serverThemes = serverThemes.filterValues { it != id },
        darkThemeID = if (darkThemeID == id) TerminalThemes.DEFAULT_DARK_ID else darkThemeID,
        lightThemeID = if (lightThemeID == id) TerminalThemes.DEFAULT_LIGHT_ID else lightThemeID,
        fixedThemeID = if (fixedThemeID == id) TerminalThemes.DEFAULT_DARK_ID else fixedThemeID,
    )

    fun zoomed(factor: Double) = copy(fontSize = (fontSize * factor).coerceIn(FONT_SIZES.start, FONT_SIZES.endInclusive))

    companion object {
        val FONT_SIZES = 8.0..32.0
        val OPACITIES = 0.3..1.0
    }
}

/** The terminal look, kept on this device */
class TerminalAppearanceStore(private val settings: SettingsStore?) {
    private val _look = MutableStateFlow(load())
    val look: StateFlow<TerminalAppearance> = _look.asStateFlow()

    fun update(change: (TerminalAppearance) -> TerminalAppearance) {
        val next = change(_look.value)
        if (next == _look.value) return
        _look.value = next
        settings?.setString(KEY, JSON.encodeToString(next))
    }

    private fun load(): TerminalAppearance =
        settings?.string(KEY)?.let { runCatching { JSON.decodeFromString<TerminalAppearance>(it) }.getOrNull() }
            ?: TerminalAppearance()

    private companion object {
        const val KEY = "terminal.appearance"
        val JSON = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    }
}
