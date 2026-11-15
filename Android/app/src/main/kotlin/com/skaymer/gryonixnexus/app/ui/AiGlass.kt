package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.app.ui.design.Gryonix

private val Violet = Color(0xFFAF52DE)

/** Frosted surface: translucent fill and a thin light rim */
@Composable
internal fun Modifier.aiGlass(shape: Shape, tint: Color? = null): Modifier {
    val fill = tint?.copy(alpha = 0.88f) ?: Gryonix.colors.cardBackground.copy(alpha = 0.72f)
    val rim = Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.55f), Color.White.copy(alpha = 0.08f)))
    return this.clip(shape).background(fill).border(1.dp, rim, shape)
}

/** Soft colour wash the glass bubbles float over */
@Composable
internal fun AiChatBackdrop() {
    Box(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground).background(
            Brush.linearGradient(
                listOf(Gryonix.colors.accent.copy(alpha = 0.14f), Color.Transparent, Violet.copy(alpha = 0.10f)),
            ),
        ),
    )
}
