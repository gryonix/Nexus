package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.ShowChart
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.ui.composed
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import com.skaymer.gryonixnexus.app.shell.ServerSection
import kotlinx.coroutines.flow.MutableStateFlow
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.ViewWeek
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.app.ui.design.ProminentButton

/** Things on screen a tour step can point at */
enum class AppTourTarget {
    SECTION_BAR, SERVER_CARD, SERVER_STRIP, SERVER_SITES, SERVER_APPS, SERVER_METRICS, SERVER_SECURITY;

    val isInsideServer: Boolean get() = this in setOf(SERVER_SITES, SERVER_APPS, SERVER_METRICS, SERVER_SECURITY)
}

/** Where each target is, in root coordinates */
object AppTourTargets {
    val frames = mutableStateMapOf<AppTourTarget, Rect>()
}

/** Reports this element's bounds for the tour's spotlight */
fun Modifier.appTourTarget(target: AppTourTarget): Modifier = composed {
    DisposableEffect(target) { onDispose { AppTourTargets.frames.remove(target) } }
    onGloballyPositioned { coordinates ->
        val bounds = coordinates.boundsInRoot()
        if (AppTourTargets.frames[target] != bounds) AppTourTargets.frames[target] = bounds
    }
}

/** The first-launch walkthrough, one step at a time */
enum class AppTourStep(
    val icon: ImageVector,
    val titleRes: Int,
    val messageRes: Int,
    val target: AppTourTarget?,
    /** The server page to show; null means the fleet */
    val section: ServerSection?,
) {
    DEMO(Icons.Filled.AutoAwesome, R.string.tour_demo_title, R.string.tour_demo_message, null, null),
    SECTION_BAR(Icons.Filled.GridView, R.string.tour_bar_title, R.string.tour_bar_message,
        AppTourTarget.SECTION_BAR, null),
    SERVER_CARD(Icons.Filled.Dns, R.string.tour_card_title, R.string.tour_card_message,
        AppTourTarget.SERVER_CARD, null),
    SERVER_STRIP(Icons.Filled.ViewWeek, R.string.tour_strip_title, R.string.tour_strip_message,
        AppTourTarget.SERVER_STRIP, ServerSection.GENERAL),
    SITES(Icons.Filled.Language, R.string.tour_sites_title, R.string.tour_sites_message,
        AppTourTarget.SERVER_SITES, ServerSection.GENERAL),
    APPS(Icons.Filled.Inventory2, R.string.tour_apps_title, R.string.tour_apps_message,
        AppTourTarget.SERVER_APPS, ServerSection.APPS),
    METRICS(Icons.Filled.ShowChart, R.string.tour_metrics_title, R.string.tour_metrics_message,
        AppTourTarget.SERVER_METRICS, ServerSection.METRICS),
    SECURITY(Icons.Filled.Shield, R.string.tour_security_title, R.string.tour_security_message,
        AppTourTarget.SERVER_SECURITY, ServerSection.GENERAL),
    FINISH(Icons.Filled.Verified, R.string.tour_finish_title, R.string.tour_finish_message, null, null);

    val next: AppTourStep? get() = entries.getOrNull(ordinal + 1)
    val previous: AppTourStep? get() = entries.getOrNull(ordinal - 1)
}

/** The current tour step, for screens that follow it */
object AppTourFocus {
    val step = MutableStateFlow<AppTourStep?>(null)

    /** A step whose screen is still scrolling into place */
    val arriving = MutableStateFlow<AppTourStep?>(null)
}

/** Dims the app and explains one tour step */
@Composable
fun AppTourOverlay(
    step: AppTourStep,
    onStep: (AppTourStep?) -> Unit,
    onConfigure: () -> Unit,
) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val density = LocalDensity.current
        val height = constraints.maxHeight.toFloat()
        val arriving = AppTourFocus.arriving.collectAsState().value == step
        val spotlight = if (arriving) null else with(density) {
            spotlightFor(step, height, 6.dp.toPx(), Metrics.listInset.toPx())
        }
        // Taps inside the spotlight reach the app
        Box(
            Modifier
                .fillMaxSize()
                .pointerInput(spotlight) {
                    awaitPointerEventScope {
                        while (true) {
                            val event = awaitPointerEvent(PointerEventPass.Initial)
                            val inside = spotlight != null && event.changes.all {
                                spotlight.contains(it.position)
                            }
                            if (!inside) event.changes.forEach { it.consume() }
                        }
                    }
                },
        )
        Dimming(spotlight)
        if (arriving) return@BoxWithConstraints
        val room = with(density) { cardRoom(spotlight, height) }
        Box(
            Modifier
                .fillMaxSize()
                .systemBarsPadding()
                .padding(start = 16.dp, end = 16.dp, top = room.top, bottom = room.bottom),
            contentAlignment = room.alignment,
        ) {
            AnimatedContent(
                targetState = step,
                transitionSpec = {
                    (slideInHorizontally { it / 3 } + fadeIn()) togetherWith
                        (slideOutHorizontally { -it / 3 } + fadeOut())
                },
                label = "tour",
            ) { shown ->
                TourCard(shown, onStep, onConfigure)
            }
        }
    }
}

private class CardRoom(val alignment: Alignment, val top: Dp, val bottom: Dp)

/** Puts the card on the roomier side of the spotlight */
private fun Density.cardRoom(spotlight: Rect?, height: Float): CardRoom {
    if (spotlight == null) return CardRoom(Alignment.Center, 0.dp, 0.dp)
    return if (spotlight.top >= height - spotlight.bottom) {
        CardRoom(Alignment.BottomCenter, 0.dp, (height - spotlight.top).toDp())
    } else {
        CardRoom(Alignment.TopCenter, spotlight.bottom.toDp(), 72.dp)
    }
}

/** The target clipped to the screen and the strip */
private fun spotlightFor(step: AppTourStep, height: Float, margin: Float, cardInset: Float): Rect? {
    val target = step.target ?: return null
    val raw = AppTourTargets.frames[target] ?: return null
    val ceiling = AppTourTargets.frames[AppTourTarget.SERVER_STRIP]
        ?.takeIf { target.isInsideServer }?.bottom ?: 0f
    val top = maxOf(raw.top, ceiling)
    val bottom = minOf(raw.bottom, height - margin, top + height * 0.34f)
    val inset = if (target.isInsideServer) cardInset else 0f
    return if (bottom - top > 8f) Rect(raw.left + inset, top, raw.right - inset, bottom) else null
}

@Composable
private fun Dimming(spotlight: Rect?) {
    val accent = Gryonix.colors.accent
    val pulse by rememberInfiniteTransition(label = "pulse").animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1100), RepeatMode.Reverse),
        label = "pulse",
    )
    Canvas(Modifier.fillMaxSize()) {
        val hole = spotlight
        val corner = CornerRadius(minOf(30.dp.toPx(), (hole?.height ?: 0f) / 2))
        val dim = Path().apply {
            fillType = PathFillType.EvenOdd
            addRect(Rect(Offset.Zero, size))
            hole?.let { addRoundRect(RoundRect(it, corner)) }
        }
        drawPath(dim, Color.Black.copy(alpha = 0.55f))
        if (hole != null) {
            drawRoundRect(accent.copy(alpha = 1f - 0.65f * pulse), hole.topLeft, hole.size, corner,
                style = Stroke(2.dp.toPx()))
        }
    }
}

@Composable
private fun TourCard(step: AppTourStep, onStep: (AppTourStep?) -> Unit, onConfigure: () -> Unit) {
    val colors = Gryonix.colors
    Column(
        Modifier
            .widthIn(max = 440.dp)
            .fillMaxWidth()
            .background(colors.cardBackground, RoundedCornerShape(26.dp))
            .padding(20.dp)
            .testTag("tour.card"),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(step.icon, contentDescription = null, tint = colors.accent, modifier = Modifier.size(28.dp))
            Spacer(Modifier.weight(1f))
            if (step != AppTourStep.FINISH) {
                PlainButton(stringResource(R.string.tour_skip), onClick = { onStep(null) },
                    modifier = Modifier.testTag("tour.skip"))
            }
        }
        Column(
            Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(stringResource(step.titleRes), style = MaterialTheme.typography.titleLarge, color = colors.label)
            Text(stringResource(step.messageRes), style = MaterialTheme.typography.bodyMedium,
                color = colors.secondaryLabel)
        }
        TourFooter(step, onStep, onConfigure)
    }
}

@Composable
private fun TourFooter(step: AppTourStep, onStep: (AppTourStep?) -> Unit, onConfigure: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Dots(step)
        Spacer(Modifier.weight(1f))
        step.previous?.let { back ->
            PlainButton(stringResource(R.string.back), onClick = { onStep(back) },
                modifier = Modifier.testTag("tour.back"))
        }
        if (step != AppTourStep.FINISH) {
            ProminentButton(stringResource(R.string.tour_next), onClick = { onStep(step.next) },
                modifier = Modifier.width(110.dp).testTag("tour.next"))
        }
    }
    if (step == AppTourStep.FINISH) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            PlainButton(stringResource(R.string.welcome_configure), onClick = onConfigure,
                modifier = Modifier.weight(1f))
            ProminentButton(stringResource(R.string.group_done), onClick = { onStep(null) },
                modifier = Modifier.weight(1f).testTag("tour.next"))
        }
    }
}

@Composable
private fun Dots(current: AppTourStep) {
    val colors = Gryonix.colors
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        AppTourStep.entries.forEach { step ->
            Box(
                Modifier
                    .height(6.dp)
                    .width(if (step == current) 16.dp else 6.dp)
                    .background(if (step == current) colors.accent else colors.tertiaryLabel, CircleShape),
            )
        }
    }
}
