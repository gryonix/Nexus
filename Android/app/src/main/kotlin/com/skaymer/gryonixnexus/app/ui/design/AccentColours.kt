package com.skaymer.gryonixnexus.app.ui.design

import androidx.compose.ui.graphics.Color
import com.skaymer.gryonixnexus.app.shell.AppAccent

fun AppAccent.colour(palette: GryonixColors): Color = when (this) {
    AppAccent.APP -> palette.accent
    AppAccent.RED -> pick(palette, 0xFFFF3B30, 0xFFFF453A)
    AppAccent.ORANGE -> pick(palette, 0xFFFF9500, 0xFFFF9F0A)
    AppAccent.YELLOW -> pick(palette, 0xFFFFCC00, 0xFFFFD60A)
    AppAccent.GREEN -> pick(palette, 0xFF34C759, 0xFF30D158)
    AppAccent.TEAL -> pick(palette, 0xFF30B0C7, 0xFF40C8E0)
    AppAccent.PURPLE -> pick(palette, 0xFFAF52DE, 0xFFBF5AF2)
    AppAccent.PINK -> pick(palette, 0xFFFF2D55, 0xFFFF375F)
    // The one system colour Apple does not split.
    AppAccent.GRAPHITE -> Color(0xFF8E8E93)
    AppAccent.BLACK -> palette.label
    AppAccent.INDIGO -> pick(palette, 0xFF5856D6, 0xFF5E5CE6)
    AppAccent.BROWN -> pick(palette, 0xFFA2845E, 0xFFAC8E68)
}

private fun pick(palette: GryonixColors, light: Long, dark: Long) =
    Color(if (palette.isDark) dark else light)

fun GryonixColors.withAccent(accent: AppAccent): GryonixColors =
    copy(accent = accent.colour(this))
