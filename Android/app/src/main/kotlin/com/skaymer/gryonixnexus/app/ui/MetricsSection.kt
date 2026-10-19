package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material3.Icon
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.CardSurface
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSegmentedControl
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.metrics.HistoryMetric
import com.skaymer.gryonixnexus.app.metrics.MetricsPreferences
import com.skaymer.gryonixnexus.app.metrics.HistoryRange
import com.skaymer.gryonixnexus.app.metrics.HistoryHost
import com.skaymer.gryonixnexus.app.metrics.HistoryViewModel
import com.skaymer.gryonixnexus.app.metrics.windowed
import com.skaymer.gryonixnexus.app.servers.FleetRepository
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DiskChoice
import com.skaymer.gryonixnexus.servercontrol.DiskHistory
import com.skaymer.gryonixnexus.servercontrol.SSHHostID

@Composable
fun HistoryExplorer(
    fleet: FleetRepository,
    history: HistoryViewModel,
    initialServerID: String? = null,
    initialHost: SSHHostID? = null,
    initialRange: HistoryRange = HistoryRange.HOUR,
    initialMetrics: Set<HistoryMetric> = setOf(HistoryMetric.CPU),
) {
    val deployments by fleet.deployments.collectAsState()

    val server: Deployment? = remember(deployments, initialServerID) {
        deployments.firstOrNull { it.id == initialServerID } ?: deployments.firstOrNull()
    }

    if (server == null) {
        EmptyHistory(R.string.no_servers, R.string.no_servers_hint)
        return
    }

    HistoryContent(
        history = history,
        server = server,
        host = initialHost,
        initialRange = initialRange,
        initialMetrics = initialMetrics,
        modifier = Modifier
            .fillMaxSize()
            .background(Gryonix.colors.groupedBackground)
            .padding(horizontal = Metrics.listInset, vertical = 12.dp),
    )
}

@Composable
fun HistoryContent(
    history: HistoryViewModel,
    server: Deployment,
    /** Which machine of that server; null falls back to `HistoryHost` */
    host: SSHHostID? = null,
    initialRange: HistoryRange = HistoryRange.HOUR,
    initialMetrics: Set<HistoryMetric> = setOf(HistoryMetric.CPU),
    modifier: Modifier = Modifier,
    onItsOwnScreen: Boolean = true,
) {
    var rangeRaw by rememberSaveable(initialRange) { mutableStateOf(initialRange.rawValue) }
    var metrics by remember(initialMetrics) { mutableStateOf(initialMetrics) }
    var choosingMetric by remember { mutableStateOf(false) }
    val offered = LocalOfferedCharts.current
    val range = HistoryRange.of(rangeRaw) ?: HistoryRange.HOUR

    LaunchedEffect(server.id, host, range.bucket) {
        history.show(server, HistoryHost.resolve(server, host), range)
    }
    DisposableEffect(Unit) { onDispose { history.stop() } }

    val state by history.state.collectAsState()
    val windowed = remember(state.points, range) { state.points.windowed(range) }
    var diskChoice by remember(server.id) { mutableStateOf<DiskChoice>(DiskChoice.Average) }
    val mounts = remember(state.diskPoints) { DiskHistory.mounts(state.diskPoints) }
    val showsDiskChoice = HistoryMetric.DISK in metrics && mounts.size > 1
    val diskLines = remember(state.diskPoints, diskChoice, showsDiskChoice) {
        if (showsDiskChoice) DiskHistory.lines(state.diskPoints, diskChoice) else emptyList()
    }
    val series = remember(windowed, metrics, diskLines) { HistoryMetric.series(metrics, windowed, diskLines) }

    Column(
        modifier,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        MetricChoiceButton(metrics) { choosingMetric = true }
        if (showsDiskChoice) DiskChoiceButton(mounts, diskChoice) { diskChoice = it }

        val plot = Modifier.fillMaxWidth().let {
            if (onItsOwnScreen) it.weight(1f, fill = false) else it
        }
        val plate: @Composable (@Composable () -> Unit) -> Unit =
            if (onItsOwnScreen) {
                { body -> CardSurface(plot) { Column(Modifier.padding(12.dp)) { body() } } }
            } else {
                { body -> Column(plot) { body() } }
            }
        plate {
            when {
                series.any { it.values.size >= 2 } -> HistoryChart(
                    series = series,
                    percentChart = HistoryMetric.isPercentChart(metrics),
                    axisLabel = { ceiling -> HistoryMetric.axisLabel(metrics, ceiling) }
                )
                state.errorMessage != null -> Text(
                    stringResource(R.string.unreachable, state.errorMessage!!),
                    color = Gryonix.colors.danger,
                    style = MaterialTheme.typography.bodySmall,
                )
                state.hasAnswered -> Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        stringResource(R.string.history_no_collector),
                        style = MaterialTheme.typography.bodyMedium,
                        color = Gryonix.colors.label,
                    )
                    Text(
                        stringResource(R.string.history_no_collector_hint),
                        style = MaterialTheme.typography.bodySmall,
                        color = Gryonix.colors.secondaryLabel,
                    )
                }
                else -> Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircularProgressIndicator(
                        Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = Gryonix.colors.tertiaryLabel,
                    )
                    Text(
                        stringResource(R.string.history_loading),
                        style = MaterialTheme.typography.bodySmall,
                        color = Gryonix.colors.secondaryLabel,
                    )
                }
            }
        }

        IOSSegmentedControl(
            segments = offered.ranges,
            selected = MetricsPreferences.resolve(range, offered.ranges),
            label = { stringResource(it.titleRes) },
            onSelect = { rangeRaw = it.rawValue },
        )
    }

    if (choosingMetric) {
        MetricChoiceSheet(
            selected = metrics,
            onDismiss = { choosingMetric = false },
            onChoose = { metrics = it },
        )
    }
}

@Composable
fun InlineHistory(
    history: HistoryViewModel,
    server: Deployment,
    host: SSHHostID,
    modifier: Modifier = Modifier,
) {
    val reader = remember(history) { history.detached() }
    HistoryContent(
        history = reader,
        server = server,
        host = host,
        modifier = modifier,
        onItsOwnScreen = false,
    )
}

@Composable
private fun MetricChoiceButton(metrics: Set<HistoryMetric>, onClick: () -> Unit) {
    val colors = Gryonix.colors
    val primary = HistoryMetric.entries.firstOrNull { it in metrics } ?: HistoryMetric.CPU
    Row(
        Modifier
            .clip(RoundedCornerShape(8.dp))
            .clickable(onClick = onClick)
            .padding(vertical = 4.dp, horizontal = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            stringResource(primary.titleRes),
            style = MaterialTheme.typography.titleMedium,
            color = colors.label,
        )
        if (metrics.size > 1) {
            Text(
                "+" + (metrics.size - 1),
                style = MaterialTheme.typography.titleSmall,
                color = colors.secondaryLabel,
            )
        }
        Icon(
            Icons.Filled.UnfoldMore,
            contentDescription = null,
            tint = colors.secondaryLabel,
            modifier = Modifier.size(16.dp),
        )
    }
}

/** Which readings the chart plots — a sheet, not a menu */
@Composable
private fun MetricChoiceSheet(
    selected: Set<HistoryMetric>,
    onDismiss: () -> Unit,
    onChoose: (Set<HistoryMetric>) -> Unit,
) {
    var current by remember(selected) { mutableStateOf(selected) }
    IOSSheet(
        title = stringResource(R.string.history_pick_metric),
        onClose = {
            onChoose(current)
            onDismiss()
        },
        closeLabel = stringResource(R.string.group_done),
    ) {
        GroupedSection(footer = stringResource(R.string.history_metric_axis_hint)) {
            val offeredMetrics = LocalOfferedCharts.current.metrics
            offeredMetrics.forEachIndexed { index, candidate ->
                CheckRow(
                    title = stringResource(candidate.titleRes),
                    checked = candidate in current,
                    onClick = { current = HistoryMetric.toggling(candidate, current) },
                    showDivider = index != offeredMetrics.lastIndex,
                )
            }
        }
    }
}

@Composable
private fun PickerRow(label: String, content: @Composable () -> Unit) {
    Column {
        Text(
            label.uppercase(),
            style = MaterialTheme.typography.bodySmall,
            color = Gryonix.colors.secondaryLabel,
            modifier = Modifier.padding(
                start = Metrics.listInset + 4.dp,
                end = Metrics.listInset + 4.dp,
                bottom = 6.dp,
            ),
        )
        content()
    }
}

@Composable
private fun EmptyHistory(title: Int, hint: Int) {
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            stringResource(title),
            style = MaterialTheme.typography.headlineSmall,
            color = Gryonix.colors.label,
        )
        Text(
            stringResource(hint),
            style = MaterialTheme.typography.bodyMedium,
            color = Gryonix.colors.secondaryLabel,
        )
    }
}

/** Short span in the app's language */
val HistoryRange.titleRes: Int
    get() = when (this) {
        HistoryRange.TEN_MINUTES -> R.string.history_range_10m
        HistoryRange.THIRTY_MINUTES -> R.string.history_range_30m
        HistoryRange.HOUR -> R.string.history_range_1h
        HistoryRange.THREE_HOURS -> R.string.history_range_3h
        HistoryRange.FIVE_HOURS -> R.string.history_range_5h
        HistoryRange.TEN_HOURS -> R.string.history_range_10h
        HistoryRange.DAY -> R.string.history_range_1d
        HistoryRange.WEEK -> R.string.history_range_1w
        HistoryRange.TWELVE_DAYS -> R.string.history_range_12d
        HistoryRange.MONTH -> R.string.history_range_1mo
        HistoryRange.SIX_MONTHS -> R.string.history_range_6mo
        HistoryRange.YEAR -> R.string.history_range_1y
    }
