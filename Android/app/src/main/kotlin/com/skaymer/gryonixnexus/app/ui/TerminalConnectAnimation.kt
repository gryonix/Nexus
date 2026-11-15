package com.skaymer.gryonixnexus.app.ui

import android.provider.Settings
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

/** False when system animations are off */
@Composable
fun animationsAllowed(): Boolean {
    val resolver = LocalContext.current.contentResolver
    return remember { Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) > 0f }
}

/** A dot that pulses while a connection is being made */
@Composable
fun PulseDot(modifier: Modifier = Modifier) {
    val animated = animationsAllowed()
    val level = if (animated) {
        rememberInfiniteTransition(label = "pulse").animateFloat(
            initialValue = 0.35f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(tween(800, easing = LinearEasing), RepeatMode.Reverse),
            label = "pulse",
        ).value
    } else {
        1f
    }
    androidx.compose.foundation.layout.Box(
        modifier.size(10.dp).alpha(level).background(MaterialTheme.colorScheme.primary, CircleShape),
    )
}

/** A short sideways shake when [trigger] changes */
@Composable
fun Modifier.shakeOn(trigger: Any?): Modifier {
    val offset = remember { Animatable(0f) }
    val animated = animationsAllowed()
    LaunchedEffect(trigger) {
        if (trigger == null || !animated) return@LaunchedEffect
        for (target in listOf(-8f, 8f, -5f, 5f, 0f)) offset.animateTo(target, tween(60))
    }
    return graphicsLayer { translationX = offset.value }
}
