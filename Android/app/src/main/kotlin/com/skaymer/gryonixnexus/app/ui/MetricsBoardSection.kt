package com.skaymer.gryonixnexus.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.CapsuleToggle
import com.skaymer.gryonixnexus.app.ui.design.CardSurface
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.IOSSegmentedControl
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.metrics.HistoryMetric
import com.skaymer.gryonixnexus.app.metrics.MetricsPreferences
import com.skaymer.gryonixnexus.app.metrics.HistoryRange
import com.skaymer.gryonixnexus.app.metrics.HistoryViewModel
import com.skaymer.gryonixnexus.app.metrics.MetricPanel
import com.skaymer.gryonixnexus.app.metrics.MetricPanelStore
import com.skaymer.gryonixnexus.app.metrics.MetricsBoardViewModel
import com.skaymer.gryonixnexus.app.metrics.windowed
import com.skaymer.gryonixnexus.app.servers.FleetRepository
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import androidx.compose.ui.unit.Dp
import java.util.UUID

/** How tall a tile's plot is */
private val TILE_CHART_HEIGHT: Dp = 96.dp

@Composable
fun MetricsSection(
    fleet: FleetRepository,
    history: HistoryViewModel,
    board: MetricsBoardViewModel,
    panels: MetricPanelStore,
    onlyServer: Deployment? = null,
    bar: MetricsBarCommands? = null,
    pushed: PushedScreen? = null,
) {
    val deployments by fleet.deployments.collectAsState()
    val stored by panels.panels.collectAsState()
    val saved = remember(stored, onlyServer) {
        if (onlyServer == null) stored else stored.filter { it.deploymentID == onlyServer.id }
    }
    val state by board.state.collectAsState()

    var editing by rememberSaveable { mutableStateOf<String?>(null) }
    var adding by rememberSaveable { mutableStateOf(false) }
    var exploring by rememberSaveable { mutableStateOf<String?>(null) }
    var arranging by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(deployments) { panels.prune(deployments) }
    LaunchedEffect(stored, deployments) { board.update(stored, deployments) }
    DisposableEffect(Unit) { onDispose { board.stop() } }

    if (onlyServer == null && deployments.isEmpty()) {
        EmptyBoard(R.string.no_servers, R.string.no_servers_hint, onAdd = null)
        return
    }

    exploring?.let { id ->
        val panel = saved.firstOrNull { it.id == id }
        BackHandler { exploring = null }
        val server = deployments.firstOrNull { it.id == panel?.deploymentID }
        val barTitle = server?.name ?: stringResource(R.string.metrics_explore)
        DisposableEffect(barTitle) {
            pushed?.push(barTitle) { exploring = null }
            onDispose { pushed?.clear() }
        }
        HistoryExplorer(
            fleet = fleet,
            history = history,
            initialServerID = panel?.deploymentID,
            initialRange = panel?.range ?: HistoryRange.HOUR,
            initialMetrics = panel?.metrics?.toSet() ?: setOf(HistoryMetric.CPU),
        )
        return
    }

    val tiles = remember(saved, state) { MetricsBoardViewModel.tiles(saved, state) }

    if (bar != null) {
        SideEffect {
            bar.canAdd = deployments.isNotEmpty()
            bar.canArrange = tiles.size > 1
        }
        LaunchedEffect(bar.pending) {
            when (bar.pending) {
                MetricsBarCommands.Command.ADD_PANEL -> adding = true
                MetricsBarCommands.Command.ARRANGE -> arranging = true
                null -> Unit
            }
            if (bar.pending != null) bar.taken()
        }
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        if (tiles.isEmpty()) {
            item {
                EmptyBoard(
                    R.string.metrics_no_panels,
                    R.string.metrics_no_panels_hint,
                    onAdd = { adding = true },
                )
            }
        }

        items(tiles.size, key = { tiles[it].panel.id }) { index ->
            val tile = tiles[index]
            PanelTile(
                tile = tile,
                server = deployments.firstOrNull { it.id == tile.panel.deploymentID },
                canMoveUp = index > 0,
                canMoveDown = index < tiles.size - 1,
                onOpen = { exploring = tile.panel.id },
                onEdit = { editing = tile.panel.id },
                onRemove = { panels.remove(tile.panel.id) },
                // Reordered against the WHOLE board — see `movedWithinView`.
                onMove = { by ->
                    panels.reorder(
                        movedWithinView(stored, tiles.map { it.panel }, index, by)
                    )
                },
            )
        }

        if (bar == null) {
            item {
                GroupedSection {
                    ActionRow(
                        text = stringResource(R.string.metrics_add_panel),
                        onClick = { adding = true },
                        showDivider = tiles.size > 1,
                    )
                    if (tiles.size > 1) {
                        ActionRow(
                            text = stringResource(R.string.metrics_arrange_panels),
                            onClick = { arranging = true },
                            showDivider = false,
                        )
                    }
                }
            }
        }
    }

    if (arranging) {
        ArrangePanelsDialog(
            panels = panels,
            shown = tiles.map { it.panel },
            servers = deployments,
            onDismiss = { arranging = false },
        )
    }

    if (adding) {
        PanelEditor(
            deployments = onlyServer?.let { listOf(it) } ?: deployments,
            panel = null,
            onCancel = { adding = false },
            onSave = { panels.add(it); adding = false },
        )
    }
    editing?.let { id ->
        val panel = saved.firstOrNull { it.id == id }
        if (panel == null) {
            editing = null
        } else {
            PanelEditor(
                deployments = onlyServer?.let { listOf(it) } ?: deployments,
                panel = panel,
                onCancel = { editing = null },
                onSave = { panels.replace(it); editing = null },
            )
        }
    }
}

internal fun swapped(panels: List<MetricPanel>, from: Int, to: Int): List<MetricPanel> {
    if (from !in panels.indices || to !in panels.indices) return panels
    val next = panels.toMutableList()
    next[from] = panels[to]
    next[to] = panels[from]
    return next
}

internal fun movedWithinView(
    stored: List<MetricPanel>,
    visible: List<MetricPanel>,
    index: Int,
    by: Int,
): List<MetricPanel> {
    val target = index + by
    if (index !in visible.indices || target !in visible.indices) return stored
    val from = stored.indexOfFirst { it.id == visible[index].id }
    val to = stored.indexOfFirst { it.id == visible[target].id }
    return swapped(stored, from, to)
}

@Composable
private fun PanelTile(
    tile: MetricsBoardViewModel.Companion.Tile,
    server: Deployment?,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    onOpen: () -> Unit,
    onEdit: () -> Unit,
    onRemove: () -> Unit,
    onMove: (Int) -> Unit,
) {
    val panel = tile.panel
    val metrics = remember(panel) { panel.metrics.toSet() }
    val windowed = remember(tile.points, panel) { tile.points.windowed(panel.range) }
    val series = remember(windowed, metrics) { HistoryMetric.series(metrics, windowed) }

    CardSurface(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = Metrics.listInset)
            .clickable(onClick = onOpen)
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                val names = HistoryMetric.entries.filter { it in metrics }
                    .map { stringResource(it.titleRes) }
                Column(Modifier.weight(1f)) {
                    Text(
                        server?.name ?: panel.deploymentID,
                        style = MaterialTheme.typography.titleLarge,
                        color = Gryonix.colors.label,
                        maxLines = 1
                    )
                    Text(
                        listOfNotNull(
                            names.joinToString(", "),
                            stringResource(panel.range.titleRes),
                            machineName(server, panel.host),
                        ).joinToString(" · "),
                        style = MaterialTheme.typography.labelSmall,
                        color = Gryonix.colors.secondaryLabel,
                        maxLines = 1
                    )
                }
                PanelMenu(canMoveUp, canMoveDown, onEdit, onRemove, onMove, onOpen)
            }

            when {
                series.any { it.values.size >= 2 } -> HistoryChart(
                    series = series,
                    percentChart = HistoryMetric.isPercentChart(metrics),
                    axisLabel = { ceiling -> HistoryMetric.axisLabel(metrics, ceiling) },
                    height = TILE_CHART_HEIGHT,
                )
                tile.errorMessage != null -> Text(
                    stringResource(R.string.unreachable, tile.errorMessage!!),
                    color = Gryonix.colors.danger,
                    style = MaterialTheme.typography.bodySmall
                )
                tile.saysThereIsNone -> Text(
                    stringResource(R.string.history_no_collector),
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.secondaryLabel,
                )
                else -> Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
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
    }
}

@Composable
private fun PanelMenu(
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    onEdit: () -> Unit,
    onRemove: () -> Unit,
    onMove: (Int) -> Unit,
    onOpen: () -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Column {
        IconButton(onClick = { open = true }, modifier = Modifier.size(28.dp)) {
            Icon(
                Icons.Filled.MoreVert,
                contentDescription = stringResource(R.string.metrics_panel_actions),
                tint = Gryonix.colors.tertiaryLabel,
                modifier = Modifier.size(20.dp),
            )
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.metrics_open_history)) },
                onClick = { open = false; onOpen() }
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.metrics_edit_panel)) },
                onClick = { open = false; onEdit() }
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.metrics_move_up)) },
                enabled = canMoveUp,
                onClick = { open = false; onMove(-1) }
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.metrics_move_down)) },
                enabled = canMoveDown,
                onClick = { open = false; onMove(1) }
            )
            DropdownMenuItem(
                text = {
                    Text(
                        stringResource(R.string.metrics_remove_panel),
                        color = Gryonix.colors.danger,
                    )
                },
                onClick = { open = false; onRemove() }
            )
        }
    }
}

/** The four choices a tile pins */
@Composable
private fun PanelEditor(
    deployments: List<Deployment>,
    panel: MetricPanel?,
    onCancel: () -> Unit,
    onSave: (MetricPanel) -> Unit,
) {
    var serverID by remember(panel) {
        mutableStateOf(panel?.deploymentID ?: deployments.first().id)
    }
    val server = deployments.firstOrNull { it.id == serverID } ?: deployments.first()
    var hostRaw by remember(panel, serverID) {
        mutableStateOf(panel?.hostRaw ?: MetricPanel.raw(server.nodes.first().sshHost))
    }
    var metrics by remember(panel) {
        mutableStateOf(panel?.metrics?.toSet() ?: setOf(HistoryMetric.CPU))
    }
    var range by remember(panel) { mutableStateOf(panel?.range ?: HistoryRange.HOUR) }
    val offeredCharts = LocalOfferedCharts.current

    val hosts = remember(server) { server.nodes.map { it.sshHost } }
    if (hosts.none { MetricPanel.raw(it) == hostRaw }) {
        hostRaw = MetricPanel.raw(hosts.first())
    }

    IOSAlert(
        title = stringResource(
            if (panel == null) R.string.metrics_add_panel else R.string.metrics_edit_panel
        ),
        onDismiss = onCancel,
        actions = listOf(
            AlertAction(stringResource(R.string.containers_cancel), onSelect = onCancel),
            AlertAction(
                stringResource(R.string.metrics_save_panel),
                preferred = true,
                onSelect = {
                    onSave(
                        MetricPanel(
                            id = panel?.id ?: UUID.randomUUID().toString(),
                            deploymentID = server.id,
                            hostRaw = hostRaw,
                            metricsRaw = HistoryMetric.entries.filter { it in metrics }
                                .map { it.key },
                            rangeRaw = range.rawValue,
                        )
                    )
                },
            ),
        ),
    ) {
        Column(
            Modifier.heightIn(max = 360.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            PickerGroup(stringResource(R.string.history_pick_server)) {
                IOSSegmentedControl(
                    segments = deployments,
                    selected = server,
                    label = { it.name },
                    onSelect = { serverID = it.id },
                )
            }
            if (hosts.size > 1) {
                PickerGroup(stringResource(R.string.metrics_pick_machine)) {
                    IOSSegmentedControl(
                        segments = server.nodes,
                        selected = server.nodes.first { MetricPanel.raw(it.sshHost) == hostRaw },
                        label = { it.name.ifEmpty { it.endpoint.host } },
                        onSelect = { hostRaw = MetricPanel.raw(it.sshHost) },
                    )
                }
            }
            PickerGroup(stringResource(R.string.history_pick_metric)) {
                Row(
                    Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    offeredCharts.metrics.forEach { candidate ->
                        CapsuleToggle(
                            text = stringResource(candidate.titleRes),
                            selected = candidate in metrics,
                            onClick = { metrics = HistoryMetric.toggling(candidate, metrics) },
                        )
                    }
                }
            }
            PickerGroup(stringResource(R.string.history_pick_range)) {
                IOSSegmentedControl(
                    segments = offeredCharts.ranges,
                    selected = MetricsPreferences.resolve(range, offeredCharts.ranges),
                    label = { stringResource(it.titleRes) },
                    onSelect = { range = it },
                )
            }
        }
    }
}

@Composable
private fun machineName(server: Deployment?, host: SSHHostID): String? {
    val nodes = server?.nodes ?: return null
    if (nodes.size < 2) return null
    val node = nodes.firstOrNull { it.sshHost == host } ?: return null
    return node.name.ifEmpty { node.endpoint.host }
}

@Composable
private fun PickerGroup(label: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            label.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            color = Gryonix.colors.secondaryLabel,
        )
        content()
    }
}

@Composable
private fun EmptyBoard(title: Int, hint: Int, onAdd: (() -> Unit)?) {
    Column(
        Modifier.fillMaxWidth().padding(24.dp),
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
        onAdd?.let {
            PlainButton(text = stringResource(R.string.metrics_add_panel), onClick = it)
        }
    }
}
