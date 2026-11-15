package com.skaymer.gryonixnexus.app.ui

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
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.skaymer.gryonixnexus.app.metrics.ChartRange
import com.skaymer.gryonixnexus.app.metrics.ChartScale
import com.skaymer.gryonixnexus.app.metrics.HistorySeries
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** History lines with grid, axes and legend */
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
    val measurer = rememberTextMeasurer()
    val labelStyle = TextStyle(fontSize = 11.sp, color = Gryonix.colors.secondaryLabel)
    val grid = Gryonix.colors.separator.copy(alpha = 0.35f)

    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Canvas(Modifier.fillMaxWidth().height(height).padding(top = 4.dp)) {
            if (start == null || end == null || end == start) return@Canvas
            val plot = ChartFrame(size.width - LABEL_GUTTER.toPx(), size.height - TIME_ROW.toPx())
            drawGrid(plot, grid, measurer, labelStyle) { axisLabel(range.floor + range.span * it) }
            drawTimes(plot, start, end, grid, measurer, labelStyle)
            series.forEachIndexed { index, line ->
                drawLine(plot, line, start, end, range, seriesColor(line.key, index, series.size))
            }
        }
        Legend(series)
    }
}

private val LABEL_GUTTER = 56.dp
private val TIME_ROW = 18.dp
private val GRID_STEPS = listOf(0.25, 0.5, 0.75)

private data class ChartFrame(val width: Float, val height: Float)

/** Light horizontal lines with their values on the right */
private fun DrawScope.drawGrid(
    plot: ChartFrame, color: Color, measurer: TextMeasurer, style: TextStyle, label: (Double) -> String,
) {
    drawLine(color, Offset(0f, plot.height), Offset(plot.width, plot.height), 1.dp.toPx())
    for (step in GRID_STEPS) {
        val y = plot.height * (1f - step.toFloat())
        drawLine(color, Offset(0f, y), Offset(plot.width, y), 0.5.dp.toPx())
        val text = measurer.measure(label(step), style)
        drawText(text, topLeft = Offset(plot.width + 6.dp.toPx(), y - text.size.height / 2f))
    }
}

/** Dashed time marks with their clock times below */
private fun DrawScope.drawTimes(
    plot: ChartFrame, start: Long, end: Long, color: Color, measurer: TextMeasurer, style: TextStyle,
) {
    val dash = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 4.dp.toPx()))
    val pattern = DateTimeFormatter.ofPattern(if (end - start > 2 * 86_400) "dd.MM" else "HH:mm")
    for (step in GRID_STEPS) {
        val x = plot.width * step.toFloat()
        drawLine(color, Offset(x, 0f), Offset(x, plot.height), 0.5.dp.toPx(), pathEffect = dash)
        val moment = Instant.ofEpochSecond(start + ((end - start) * step).toLong()).atZone(ZoneId.systemDefault())
        val text = measurer.measure(pattern.format(moment), style)
        drawText(text, topLeft = Offset(x - text.size.width / 2f, plot.height + 3.dp.toPx()))
    }
}

private fun DrawScope.drawLine(
    plot: ChartFrame, line: HistorySeries, start: Long, end: Long, range: ChartRange, color: Color,
) {
    if (line.values.size < 2) return
    val path = Path()
    line.values.forEachIndexed { position, sample ->
        val x = plot.width * (sample.date.epochSecond - start).toFloat() / (end - start).toFloat()
        val y = plot.height * (1f - ((sample.value - range.floor) / range.span).coerceIn(0.0, 1.0).toFloat())
        if (position == 0) path.moveTo(x, y) else path.lineTo(x, y)
    }
    drawPath(path, color, style = Stroke(width = 2.dp.toPx()))
}

/** Coloured dots and names under the chart */
@Composable
private fun Legend(series: List<HistorySeries>) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        series.forEachIndexed { index, line ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Canvas(Modifier.size(8.dp)) { drawCircle(seriesColor(line.key, index, series.size)) }
                Text(
                    line.label ?: stringResource(line.nameRes),
                    style = MaterialTheme.typography.labelSmall,
                    color = Gryonix.colors.secondaryLabel,
                    maxLines = 1,
                )
            }
        }
    }
}

/** The iOS colour of a series */
internal fun seriesColor(key: String, index: Int, count: Int): Color = when (key) {
    "cpu", "rx", "read" -> Color(0xFF0A84FF)
    "mem" -> Color(0xFFAF52DE)
    "tx", "write", "swap" -> Color(0xFFFF9500)
    "disk" -> Color(0xFF30B0C7)
    "load" -> Color(0xFF5856D6)
    "temp" -> Color(0xFFFF9500)
    "power" -> Color(0xFFFFCC00)
    else -> listOf(
        Color(0xFF0A84FF), Color(0xFFAF52DE), Color(0xFF30B0C7),
        Color(0xFF34C759), Color(0xFFFF2D55)
    )[index % 5].takeIf { count > 0 } ?: Color(0xFF0A84FF)
}
