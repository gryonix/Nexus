package com.skaymer.gryonixnexus.app.ui.design

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.flow.filter

private val WHEEL_LINE = 40.dp
private const val WHEEL_LINES = 3

/** A row with a wheel under it */
@Composable
fun WheelRow(
    title: String,
    choices: List<String>,
    selected: Int,
    onSelect: (Int) -> Unit,
    showDivider: Boolean = true,
    infoNote: String? = null,
) {
    var open by remember { mutableStateOf(false) }
    val colors = Gryonix.colors
    ValueRow(
        title = title,
        value = choices.getOrNull(selected),
        onClick = { open = !open },
        showDivider = showDivider && !open,
        chevron = {},
        valueColor = if (open) colors.accent else colors.secondaryLabel,
        infoNote = infoNote,
    )
    if (open) {
        Wheel(choices, selected, onSelect)
        if (showDivider) {
            Box(Modifier.padding(start = 16.dp).fillMaxWidth().height(0.5.dp).background(colors.separator))
        }
    }
}

/** Index of the line resting in the middle */
private fun LazyListState.middle(linePx: Float): Int =
    firstVisibleItemIndex + if (firstVisibleItemScrollOffset > linePx / 2) 1 else 0

@Composable
private fun Wheel(choices: List<String>, selected: Int, onSelect: (Int) -> Unit) {
    val state = rememberLazyListState(initialFirstVisibleItemIndex = selected.coerceAtLeast(0))
    val linePx = with(LocalDensity.current) { WHEEL_LINE.toPx() }
    val middle by remember { derivedStateOf { state.middle(linePx) } }
    val wanted by rememberUpdatedState(selected)
    val report by rememberUpdatedState(onSelect)
    LaunchedEffect(state) {
        snapshotFlow { state.isScrollInProgress }.filter { !it }.collect {
            val rested = state.middle(linePx)
            if (rested != wanted && rested in choices.indices) report(rested)
        }
    }
    LaunchedEffect(selected) {
        if (!state.isScrollInProgress && state.middle(linePx) != selected && selected >= 0) state.scrollToItem(selected)
    }
    Box(Modifier.fillMaxWidth().height(WHEEL_LINE * WHEEL_LINES), contentAlignment = Alignment.Center) {
        Box(
            Modifier.padding(horizontal = 16.dp).fillMaxWidth().height(WHEEL_LINE)
                .clip(RoundedCornerShape(8.dp)).background(Gryonix.colors.trackFill),
        )
        LazyColumn(
            state = state,
            flingBehavior = rememberSnapFlingBehavior(state),
            contentPadding = PaddingValues(vertical = WHEEL_LINE * (WHEEL_LINES / 2)),
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.fillMaxWidth(),
        ) {
            items(choices.size) { index -> WheelLine(choices[index], index == middle) }
        }
    }
}

@Composable
private fun WheelLine(text: String, centered: Boolean) {
    Box(Modifier.fillMaxWidth().height(WHEEL_LINE), contentAlignment = Alignment.Center) {
        Text(
            text,
            style = MaterialTheme.typography.bodyLarge,
            color = if (centered) Gryonix.colors.label else Gryonix.colors.tertiaryLabel,
            maxLines = 1,
        )
    }
}
