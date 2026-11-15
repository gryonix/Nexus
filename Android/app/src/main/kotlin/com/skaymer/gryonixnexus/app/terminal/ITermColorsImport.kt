package com.skaymer.gryonixnexus.app.terminal

import java.util.UUID

/** Reads an iTerm2 `.itermcolors` plist into a theme */
object ITermColorsImport {
    class Failure(message: String) : Exception(message)

    private val entry = Regex("<key>([^<]+)</key>\\s*<dict>(.*?)</dict>", RegexOption.DOT_MATCHES_ALL)
    private val component = Regex("<key>(Red|Green|Blue) Component</key>\\s*<real>([^<]+)</real>")

    fun theme(text: String, name: String): TerminalTheme {
        val colours = entry.findAll(text).associate { it.groupValues[1] to it.groupValues[2] }
        if (colours.isEmpty()) throw Failure("not a colour file")
        fun colour(key: String): String? {
            val parts = component.findAll(colours[key] ?: return null)
                .associate { it.groupValues[1] to it.groupValues[2].trim().toDoubleOrNull() }
            return TerminalTheme.hex(
                parts["Red"] ?: return null,
                parts["Green"] ?: return null,
                parts["Blue"] ?: return null,
            )
        }
        val ansi = (0 until 16).map { colour("Ansi $it Color") ?: throw Failure("Ansi $it Color") }
        val background = colour("Background Color") ?: throw Failure("Background Color")
        val foreground = colour("Foreground Color") ?: throw Failure("Foreground Color")
        return TerminalTheme(
            id = "custom-" + UUID.randomUUID().toString().lowercase(),
            name = name,
            background = background,
            foreground = foreground,
            cursor = colour("Cursor Color") ?: foreground,
            selection = colour("Selection Color") ?: ansi[8],
            ansi = ansi,
        )
    }
}
