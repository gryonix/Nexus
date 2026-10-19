package com.skaymer.gryonixnexus.app.terminal

import androidx.compose.ui.graphics.Color

/** The 256 colours a shell talks in, as pixels */
object TerminalPalette {
    val background = Color(0xFF10121A)
    val foreground = Color(0xFFE6E6E6)

    private val basic = intArrayOf(
        0x000000, 0xCD3131, 0x0DBC79, 0xE5E510, 0x2472C8, 0xBC3FBC, 0x11A8CD, 0xE5E5E5,
        0x666666, 0xF14C4C, 0x23D18B, 0xF5F543, 0x3B8EEA, 0xD670D6, 0x29B8DB, 0xFFFFFF,
    )

    fun colour(index: Int?, fallback: Color): Color {
        val value = index ?: return fallback
        return when {
            value < 16 -> Color(0xFF000000L.toInt() or basic[value])
            value < 232 -> {
                val offset = value - 16
                Color(
                    red = LEVELS[offset / 36] / 255f,
                    green = LEVELS[(offset / 6) % 6] / 255f,
                    blue = LEVELS[offset % 6] / 255f,
                )
            }
            value < 256 -> {
                val grey = (8 + (value - 232) * 10) / 255f
                Color(red = grey, green = grey, blue = grey)
            }
            else -> fallback
        }
    }

    private val LEVELS = intArrayOf(0, 95, 135, 175, 215, 255)
}
