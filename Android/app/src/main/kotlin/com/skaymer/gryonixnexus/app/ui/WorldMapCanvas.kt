package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloseFullscreen
import androidx.compose.material.icons.filled.OpenInFull
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import kotlin.math.PI
import kotlin.math.pow
import kotlin.math.sin

/** The world map with picked countries in the accent colour */
@Composable
fun WorldMapCanvas(
    selected: Set<String>,
    description: String,
    onToggle: (String) -> Unit,
    modifier: Modifier = Modifier,
    /** Shows the corner button for full screen */
    onExpand: (() -> Unit)? = null,
    /** Takes the whole space instead of the map's own proportions */
    fillsSpace: Boolean = false,
) {
    val context = LocalContext.current
    val map = remember { WorldMap.load(context.assets) }
    val paths = remember(map) { map.countries.mapValues { (_, c) -> c.toPath() } }
    val shaped = remember(map) { map.countries.filterValues { !it.isTiny } }
    val dots = remember(map) { map.countries.filterValues { it.isTiny } }
    val land = remember(paths) {
        Path().apply { shaped.keys.forEach { addPath(paths.getValue(it)) } }
    }
    val transitions = remember { mutableStateMapOf<String, MapTransition>() }
    var previous by remember { mutableStateOf(selected) }
    var now by remember { mutableLongStateOf(0L) }
    val toggle by rememberUpdatedState(onToggle)

    LaunchedEffect(selected) {
        val old = previous
        previous = selected
        if (old == selected) return@LaunchedEffect
        val start = withFrameMillis { it }
        now = start
        record(transitions, map, turnedOn = selected - old, turnedOff = old - selected, start)
        while (transitions.values.any { !it.isFinished(now) }) now = withFrameMillis { it }
        transitions.entries.removeAll { it.value.isFinished(now) }
    }

    var viewport by remember(map) { mutableStateOf(MapViewport(map.width, map.height)) }
    var canvasWidth by remember { mutableFloatStateOf(0f) }
    var canvasHeight by remember { mutableFloatStateOf(0f) }
    val colors = Gryonix.colors
    val painter = WorldMapPainter(
        map, paths, land, shaped, dots, selected, transitions.toMap(), now, viewport,
        landColour = colors.label.copy(alpha = 0.14f), accent = colors.accent,
        border = colors.cardBackground,
    )
    Box(modifier) {
        Canvas(
            Modifier
                .then(if (fillsSpace) Modifier.fillMaxSize()
                      else Modifier.fillMaxWidth().aspectRatio(map.width / map.height))
                .clip(RoundedCornerShape(14.dp))
                .onSizeChanged {
                    canvasWidth = it.width.toFloat()
                    canvasHeight = it.height.toFloat()
                }
                .semantics { contentDescription = description }
                .pointerInput(map) {
                    detectTransformGestures { centroid, pan, zoom, _ ->
                        val width = size.width.toFloat()
                        val height = size.height.toFloat()
                        viewport = viewport
                            .zoom(zoom, centroid.x, centroid.y, width, height)
                            .pan(pan.x, pan.y, width, height)
                    }
                }
                .pointerInput(map) {
                    detectTapGestures(
                        onDoubleTap = {
                            viewport = viewport.reset(size.width.toFloat(), size.height.toFloat())
                        },
                        onTap = { offset ->
                            val width = size.width.toFloat()
                            val height = size.height.toFloat()
                            val perUnit = viewport.pointsPerUnit(width, height)
                            if (perUnit <= 0f) return@detectTapGestures
                            map.countryAt(
                                viewport.mapX(offset.x, width, height),
                                viewport.mapY(offset.y, width, height),
                                tolerance = 14.dp.toPx() / perUnit,
                            )?.let(toggle)
                        },
                    )
                },
        ) { painter.paint(this) }
        if (viewport.isZoomedIn) {
            IconButton(
                onClick = { viewport = viewport.reset(canvasWidth, canvasHeight) },
                modifier = Modifier.align(Alignment.TopEnd),
            ) {
                Icon(
                    Icons.Filled.CloseFullscreen,
                    contentDescription = stringResource(R.string.security_map_whole_world),
                    tint = colors.accent,
                )
            }
        }
        if (onExpand != null) {
            IconButton(onClick = onExpand, modifier = Modifier.align(Alignment.BottomEnd)) {
                Icon(
                    Icons.Filled.OpenInFull,
                    contentDescription = stringResource(R.string.security_map_full_screen),
                    tint = colors.accent,
                )
            }
        }
    }
}

private fun record(
    transitions: MutableMap<String, MapTransition>,
    map: WorldMap,
    turnedOn: Set<String>,
    turnedOff: Set<String>,
    start: Long,
) {
    for ((codes, isOn) in listOf(turnedOn to true, turnedOff to false)) {
        val delays = MapTransition.staggered(codes, map)
        codes.forEach { transitions[it] = MapTransition(isOn, start + (delays[it] ?: 0L)) }
    }
}

private fun WorldMap.Country.isVisible(left: Float, top: Float, width: Float, height: Float):
    Boolean = maxX >= left - 1f && minX <= left + width + 1f &&
    maxY >= top - 1f && minY <= top + height + 1f

private fun WorldMap.Country.toPath() = Path().apply {
    for (ring in rings) {
        if (ring.size < 6) continue
        moveTo(ring[0], ring[1])
        for (i in 2 until ring.size - 1 step 2) lineTo(ring[i], ring[i + 1])
        close()
    }
}

/** Draws land, picked countries and their transitions */
private class WorldMapPainter(
    val map: WorldMap,
    val paths: Map<String, Path>,
    val land: Path,
    val shaped: Map<String, WorldMap.Country>,
    val dots: Map<String, WorldMap.Country>,
    val selected: Set<String>,
    val transitions: Map<String, MapTransition>,
    val now: Long,
    val viewport: MapViewport,
    val landColour: Color,
    val accent: Color,
    val border: Color,
) {
    fun paint(scope: DrawScope) = with(scope) {
        val s = viewport.pointsPerUnit(size.width, size.height)
        if (s <= 0f) return@with
        val u = density / s
        val left = viewport.visibleX(size.width, size.height)
        val top = viewport.visibleY(size.width, size.height)
        scale(s, pivot = Offset.Zero) {
            translate(-left, -top) {
                drawPath(land, landColour)
                val width = viewport.visibleWidth(size.width, size.height)
                val height = viewport.visibleHeight(size.width, size.height)
                shaped.forEach { (code, country) ->
                    if (country.isVisible(left, top, width, height)) paintShape(code, country, u)
                }
                drawPath(land, border, style = Stroke(0.7f * u))
                dots.forEach { (code, country) ->
                    if (country.isVisible(left, top, width, height)) paintDot(code, country, u)
                }
            }
        }
    }

    private fun DrawScope.paintShape(code: String, country: WorldMap.Country, u: Float) {
        val path = paths.getValue(code)
        val transition = transitions[code]
        if (transition == null) {
            if (code in selected) drawPath(path, accent)
            return
        }
        val eased = easeOut(transition.progress(now))
        val reach = country.reach * 1.05f
        val radius = if (transition.isOn) reach * eased else reach * (1 - eased)
        val center = Offset(country.centerX, country.centerY)
        if (radius > 0f) {
            clipPath(Path().apply { addOval(circle(center, radius)) }) { drawPath(path, accent) }
        }
        if (transition.isOn && eased > 0f && eased < 1f) {
            drawCircle(accent.copy(alpha = (1 - eased) * 0.8f), reach * eased + 10f * u, center,
                style = Stroke(2f * u))
        }
    }

    private fun DrawScope.paintDot(code: String, country: WorldMap.Country, u: Float) {
        val center = Offset(country.centerX, country.centerY)
        val isOn = code in selected
        val transition = transitions[code]
        if (transition == null) {
            drawCircle(if (isOn) accent else landColour, (if (isOn) 3f else 1.6f) * u, center)
            return
        }
        val p = transition.progress(now)
        val base = (if (transition.isOn) 3f else 1.6f + 1.4f * (1 - p)) * u
        val pop = base * (1 + 1.2f * sin(PI.toFloat() * p))
        drawCircle(if (transition.isOn || p < 1f) accent else landColour, pop, center)
        if (transition.isOn && p > 0f && p < 1f) {
            drawCircle(accent.copy(alpha = 1 - p), (4 + 14 * p) * u, center, style = Stroke(1.5f * u))
        }
    }

    private fun circle(center: Offset, radius: Float) =
        androidx.compose.ui.geometry.Rect(center, radius)

    private fun easeOut(t: Float) = 1 - (1 - t).pow(3)
}
