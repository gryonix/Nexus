package com.skaymer.gryonixnexus.app.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import com.google.zxing.qrcode.encoder.Encoder
import com.skaymer.gryonixnexus.app.shell.Haptics
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.LocalHaptics
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/** The QR code as rows of dark and light modules */
object QuickTransferModules {
    fun grid(text: String): List<BooleanArray> {
        val matrix = Encoder.encode(text, ErrorCorrectionLevel.M).matrix
        return (0 until matrix.height).map { y -> BooleanArray(matrix.width) { x -> matrix.get(x, y).toInt() == 1 } }
    }

    /** Repeatable pseudo-random numbers in 0..1 */
    fun noise(a: Int, b: Int): Float {
        var hash = (a * 73_856_093 xor b * 19_349_663).toLong() and 0xffffffffL
        hash = (hash xor (hash ushr 13)) * 0x5bd1e995L
        return ((hash and Long.MAX_VALUE) % 1000) / 1000f
    }
}

/** A QR code that can scatter into flying dots */
@Composable
fun QuickTransferQrCode(modules: List<BooleanArray>, scattered: Boolean, label: String, modifier: Modifier = Modifier) {
    val time = remember { Animatable(0f) }
    LaunchedEffect(scattered) {
        if (scattered) time.animateTo(1.1f, tween(1100, easing = LinearEasing)) else time.snapTo(0f)
    }
    val card by animateFloatAsState(if (scattered) 0f else 1f, tween(600), label = "qr card")
    val accent = Gryonix.colors.accent
    Canvas(
        modifier
            .widthIn(max = 320.dp)
            .fillMaxWidth()
            .aspectRatio(1f)
            .clip(RoundedCornerShape(24.dp))
            .background(Color.White.copy(alpha = card))
            .semantics { contentDescription = label },
    ) {
        drawModules(modules, time.value, accent)
    }
}

private fun DrawScope.drawModules(modules: List<BooleanArray>, time: Float, accent: Color) {
    if (modules.isEmpty()) return
    val cell = size.width / (modules.size + 4)
    val centre = Offset(size.width / 2, size.height / 2)
    modules.forEachIndexed { row, line ->
        line.forEachIndexed { column, dark ->
            if (!dark) return@forEachIndexed
            val seed = QuickTransferModules.noise(row, column)
            val progress = ((time - seed * 0.35f) / 0.75f).coerceIn(0f, 1f)
            if (progress >= 1f) return@forEachIndexed
            val origin = Offset((column + 2) * cell, (row + 2) * cell)
            drawModule(origin, cell, centre, seed, progress, accent)
        }
    }
}

private fun DrawScope.drawModule(origin: Offset, cell: Float, centre: Offset, seed: Float, progress: Float, accent: Color) {
    val dx = origin.x - centre.x
    val dy = origin.y - centre.y
    val length = max(1f, sqrt(dx * dx + dy * dy))
    val push = size.width * progress * progress * (0.6f + seed)
    val point = Offset(origin.x + dx / length * push - dy / length * push * 0.3f, origin.y + dy / length * push + dx / length * push * 0.3f)
    val side = cell * (1 - progress * 0.55f)
    if (progress > 0f) {
        drawCircle(accent.copy(alpha = 1 - progress), side / 2, Offset(point.x + side / 2, point.y + side / 2))
    } else {
        drawRect(Color.Black, point, Size(side + 0.5f, side + 0.5f))
    }
}

/** Dots running from one device to the other */
@Composable
fun QuickTransferDots(from: ImageVector, to: ImageVector) {
    val accent = Gryonix.colors.accent
    val phase by rememberInfiniteTransition(label = "dots").animateFloat(
        0f, 1f, infiniteRepeatable(tween(1400, easing = LinearEasing), RepeatMode.Restart), label = "dots phase",
    )
    Row(Modifier.fillMaxWidth().padding(vertical = 56.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(from, null, Modifier.size(44.dp), tint = accent)
        Canvas(Modifier.weight(1f).height(24.dp)) {
            for (index in 0 until 6) {
                val p = (phase + index / 6f) % 1f
                val swell = sin(p * PI).toFloat()
                val y = size.height / 2 - sin(p * PI * 2).toFloat() * 4.dp.toPx()
                drawCircle(accent.copy(alpha = 0.25f + 0.75f * swell), (3 + 3 * swell).dp.toPx(), Offset(size.width * p, y))
            }
        }
        Icon(to, null, Modifier.size(44.dp), tint = accent)
    }
}

/** Dots gather into the arrived server cards */
@Composable
fun QuickTransferArrival(names: List<String>) {
    val gather = remember { Animatable(0f) }
    var landed by remember { mutableStateOf(false) }
    val haptics = LocalHaptics.current
    val accent = Gryonix.colors.accent
    LaunchedEffect(Unit) {
        gather.animateTo(1f, tween(800, easing = FastOutSlowInEasing))
        landed = true
        haptics(Haptics.Feel.SUCCESS)
    }
    Box(Modifier.fillMaxWidth().heightIn(min = 220.dp), contentAlignment = Alignment.Center) {
        if (!landed) {
            Canvas(Modifier.fillMaxWidth().height(220.dp)) { drawGather(gather.value, accent) }
        }
        AnimatedVisibility(landed, enter = scaleIn(spring(dampingRatio = 0.6f), initialScale = 0.6f) + fadeIn()) {
            ArrivedCards(names)
        }
    }
}

private fun DrawScope.drawGather(progress: Float, accent: Color) {
    val eased = 1 - (1 - min(1f, progress)).pow(3)
    for (index in 0 until 48) {
        val angle = QuickTransferModules.noise(index, 7) * 2 * PI
        val distance = (0.5f + QuickTransferModules.noise(index, 3)) * size.width * 0.6f * (1 - eased)
        val point = Offset(center.x + (cos(angle) * distance).toFloat(), center.y + (sin(angle) * distance).toFloat())
        drawCircle(accent.copy(alpha = 0.3f + 0.7f * eased), 3.dp.toPx(), point)
    }
}

@Composable
private fun ArrivedCards(names: List<String>) {
    val colors = Gryonix.colors
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(Icons.Filled.CheckCircle, null, Modifier.size(56.dp), tint = colors.success)
        names.take(4).forEach { name ->
            Row(
                Modifier
                    .widthIn(max = 280.dp)
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(colors.cardBackground)
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.Dns, null, Modifier.size(20.dp), tint = colors.accent)
                Spacer(Modifier.width(10.dp))
                Text(name, color = colors.label, maxLines = 1)
            }
        }
        if (names.size > 4) Text("+${names.size - 4}", color = colors.secondaryLabel)
    }
}

/** The four-digit check code, large */
@Composable
fun QuickTransferCodeBadge(code: String) {
    val colors = Gryonix.colors
    Text(
        code,
        modifier = Modifier
            .clip(RoundedCornerShape(20.dp))
            .background(colors.cardBackground)
            .padding(horizontal = 28.dp, vertical = 14.dp),
        style = MaterialTheme.typography.displayMedium.copy(
            fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold, letterSpacing = 10.sp,
        ),
        color = colors.label,
    )
}
