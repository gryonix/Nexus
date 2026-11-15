package com.skaymer.gryonixnexus.app.ui

import android.graphics.Typeface
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.composed
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.app.terminal.TerminalPalette
import com.skaymer.gryonixnexus.app.terminal.TerminalTheme

/** A theme as pixels */
class TerminalInk(
    val background: Color,
    val foreground: Color,
    val cursor: Color,
    val ansi: List<Color>,
) {
    companion object {
        fun color(hex: String): Color {
            val (red, green, blue) = TerminalTheme.rgb(hex) ?: return Color.Black
            return Color(red, green, blue)
        }

        fun of(theme: TerminalTheme) = TerminalInk(
            color(theme.background),
            color(theme.foreground),
            color(theme.cursor),
            theme.ansi.map(::color).ifEmpty { TerminalPalette.defaultAnsi },
        )
    }
}

object TerminalFonts {
    /** Font names to offer; null is system monospace */
    val choices: List<String?> = listOf(null, "serif-monospace")

    fun title(name: String?): String? = name?.let { "Courier style" }

    fun family(name: String?): FontFamily =
        name?.let { FontFamily(Typeface.create(it, Typeface.NORMAL)) } ?: FontFamily.Monospace
}

/** Two fingers change the font size */
fun Modifier.pinchToZoom(onZoom: (Double) -> Unit): Modifier = composed {
    val latest = rememberUpdatedState(onZoom)
    pointerInput(Unit) {
        awaitEachGesture {
            awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
            do {
                val event = awaitPointerEvent(PointerEventPass.Initial)
                if (event.changes.size >= 2) {
                    val zoom = event.calculateZoom()
                    if (zoom != 1f) latest.value(zoom.toDouble())
                    event.changes.forEach { it.consume() }
                }
            } while (event.changes.any { it.pressed })
        }
    }
}

/** Opens the terminal design settings */
@Composable
fun DesignButton(ink: TerminalInk, onClick: () -> Unit, modifier: Modifier) {
    Text(
        "Aa",
        style = MaterialTheme.typography.labelMedium,
        color = ink.foreground.copy(alpha = 0.6f),
        modifier = modifier.clickable(onClick = onClick).padding(10.dp),
    )
}
