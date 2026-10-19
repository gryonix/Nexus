package com.skaymer.gryonixnexus.app.ui

import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.app.metrics.ChartScale
import com.skaymer.gryonixnexus.app.metrics.HistorySeries

/** The history lines */
@Composable
fun HistoryChart(
    series: List<HistorySeries>,
    percentChart: Boolean,
    axisLabel: (Double) -> String,
    /** How tall the plot is */
    height: Dp = 180.dp,
    modifier: Modifier = Modifier
) {
    val samples = series.flatMap { it.values }
    val start = samples.minOfOrNull { it.date.epochSecond }
    val end = samples.maxOfOrNull { it.date.epochSecond }
    val range = ChartScale.of(samples.map { it.value }, percentChart, LocalChartAutoScale.current)
    val ceiling = range.ceiling
    val floor = range.floor

    Column(modifier) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            series.forEachIndexed { index, line ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Canvas(Modifier.size(8.dp)) { drawCircle(colorOf(index, series.size)) }
                    Text(line.label ?: stringResource(line.nameRes), style = MaterialTheme.typography.labelSmall, maxLines = 1)
                }
            }
        }
        Canvas(
            Modifier
                .fillMaxWidth()
                .height(height)
                .padding(top = 8.dp, bottom = 4.dp)
        ) {
            if (start == null || end == null || end == start) return@Canvas
            val width = size.width
            val height = size.height
            series.forEachIndexed { index, line ->
                if (line.values.size < 2) return@forEachIndexed
                val path = Path()
                line.values.forEachIndexed { position, sample ->
                    val x = width * (sample.date.epochSecond - start).toFloat() / (end - start).toFloat()
                    val y = height * (1f - ((sample.value - floor) / range.span).coerceIn(0.0, 1.0).toFloat())
                    if (position == 0) path.moveTo(x, y) else path.lineTo(x, y)
                }
                drawPath(path, colorOf(index, series.size), style = Stroke(width = 2.dp.toPx()))
            }
            drawLine(
                Color.Gray.copy(alpha = 0.4f),
                Offset(0f, height),
                Offset(width, height),
                strokeWidth = 1.dp.toPx()
            )
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(axisLabel(ceiling), style = MaterialTheme.typography.labelSmall)
            if (floor > 0) {
                Text(axisLabel(floor), style = MaterialTheme.typography.labelSmall)
            }
        }
    }
}

private fun colorOf(index: Int, count: Int): Color = when {
    count == 2 -> if (index == 0) Color(0xFF0A84FF) else Color(0xFFFF9500)
    else -> listOf(
        Color(0xFF0A84FF), Color(0xFFAF52DE), Color(0xFF30B0C7),
        Color(0xFF34C759), Color(0xFFFF2D55)
    )[index % 5]
}
