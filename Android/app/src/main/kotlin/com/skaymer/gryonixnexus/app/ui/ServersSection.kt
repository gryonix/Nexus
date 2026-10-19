package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.produceState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.size
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.cardSurface
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.security.GatedAction
import com.skaymer.gryonixnexus.app.security.rememberGuard
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.app.servers.DeploymentTransferService
import com.skaymer.gryonixnexus.app.servers.FleetMetrics
import com.skaymer.gryonixnexus.app.servers.FleetRepository
import com.skaymer.gryonixnexus.app.servers.HostMetricsState
import com.skaymer.gryonixnexus.app.servers.WakeOnLANViewModel
import com.skaymer.gryonixnexus.app.servers.LocalNetworkCheck
import com.skaymer.gryonixnexus.app.servers.WakeButtonSettings
import com.skaymer.gryonixnexus.app.servers.MetricsDisplaySettings
import com.skaymer.gryonixnexus.app.servers.ServerCardColumns
import com.skaymer.gryonixnexus.app.servers.ServerCardLayout
import com.skaymer.gryonixnexus.app.servers.ServerTint
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.MetricsIndicatorStyle
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.ServerCardSize
import com.skaymer.gryonixnexus.servercontrol.ServerGroups
import kotlinx.coroutines.delay

@Composable
fun ServersSection(
    fleet: FleetRepository,
    store: SettingsStore,
    metrics: FleetMetrics,
    onOpen: (String) -> Unit,
    onForget: (String) -> Unit,
    /** Moving a server between devices */
    transfer: DeploymentTransferService,
    /** Where the machines' passwords and host-key pins live */
    secrets: SecretStore,
    /** The bar's own menu, drawn by the shell */
    bar: FleetBarCommands,
    /** Adding a server is the shell's screen, not this one's */
    onAddServer: () -> Unit,
    /** Wakes a sleeping home machine from its card */
    onWake: (Deployment) -> Unit = {},
) {
    val revision by store.revision.collectAsState()
    val deployments by fleet.deployments.collectAsState()

    val fallback = remember(revision) {
        ServerCardColumns.of(store.string(ServerCardColumns.KEY)).cardSize
    }
    val wakeAfter = remember(revision) { WakeButtonSettings.delay(store) }
    val defaultStyle = remember(revision) {
        MetricsDisplaySettings.indicatorStyle(
            store.string(MetricsDisplaySettings.INDICATOR_STYLE_KEY)
        )
    }
    var group by remember { mutableStateOf<String?>(null) }
    var warning by remember { mutableStateOf<Deployment?>(null) }
    val guard = rememberGuard()
    val exportSeveralReason = stringResource(R.string.export_several_unlock_reason)
    var connectionFor by remember { mutableStateOf<Deployment?>(null) }
    var accessFor by remember { mutableStateOf<Deployment?>(null) }
    var reordering by remember { mutableStateOf(false) }
    var choosingExports by remember { mutableStateOf(false) }

    val transferUi = rememberServerTransfer(transfer, known = { fleet.deployments.value }, onImported = { fleet.reload() })
    val shown = remember(deployments, group) {
        group?.let { name -> ServerGroups.members(name, deployments) } ?: deployments
    }
    val rows = remember(shown, fallback) { ServerCardLayout.rows(shown, fallback) }

    SideEffect { bar.count = deployments.size }
    LaunchedEffect(bar.pending) {
        when (bar.pending) {
            FleetBarCommands.Command.ADD_SERVER -> onAddServer()
            FleetBarCommands.Command.IMPORT -> transferUi.import()
            FleetBarCommands.Command.EXPORT_SEVERAL -> choosingExports = true
            FleetBarCommands.Command.REORDER -> reordering = true
            null -> Unit
        }
        if (bar.pending != null) bar.taken()
    }

    if (deployments.isEmpty()) {
        EmptyFleet()
        return
    }

    Column(Modifier.fillMaxSize()) {
        ServerGroupsStrip(
            deployments = deployments,
            selected = group,
            onSelect = { group = it },
            fleet = fleet,
            onReorder = { reordering = true },
            onExportSeveral = { choosingExports = true },
        )
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(horizontal = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 12.dp)
        ) {
            items(rows, key = { row -> row.first().id }) { row ->
                Row(
                    modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    row.forEach { deployment ->
                        ServerCard(
                            deployment = deployment,
                            metrics = metrics,
                            onWake = { onWake(deployment) },
                            wakeAfter = wakeAfter,
                            style = ServerCardLayout.indicatorStyle(deployment, defaultStyle),
                            onOpen = { onOpen(deployment.id) },
                            compact = row.size > 1 ||
                                ServerCardLayout.size(deployment, fallback) == ServerCardSize.COMPACT,
                            onSize = { fleet.setCardSize(deployment.id, it) },
                            onIndicator = { fleet.setIndicatorStyle(deployment.id, it) },
                            onTint = { fleet.setTint(deployment.id, it) },
                            onForget = { onForget(deployment.id) },
                            onExport = {
                                guard(GatedAction.EXPORT, deployment.name) {
                                    warning = deployment
                                }
                            },
                            onConnection = { connectionFor = deployment },
                            onAccess = { accessFor = deployment },
                            modifier = Modifier.weight(1f).fillMaxHeight().then(
                                if (deployment.id == rows.first().first().id) {
                                    Modifier.appTourTarget(AppTourTarget.SERVER_CARD)
                                } else {
                                    Modifier
                                }
                            )
                        )
                    }
                    if (row.size == 1 &&
                        ServerCardLayout.size(row[0], fallback) == ServerCardSize.COMPACT
                    ) {
                        Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
    }

    warning?.let { deployment ->
        ConfirmAlert(
            title = stringResource(R.string.export_server),
            message = stringResource(R.string.export_server_warning),
            confirm = stringResource(R.string.export_server_confirm),
            cancel = stringResource(R.string.group_cancel),
            destructive = true,
            onConfirm = {
                warning = null
                transferUi.exportOne(deployment)
            },
            onCancel = { warning = null },
        )
    }

    if (choosingExports) {
        ExportSeveralDialog(
            deployments = deployments,
            onDismiss = { choosingExports = false },
            onChosen = { chosen ->
                choosingExports = false
                if (chosen.isNotEmpty()) {
                    guard(GatedAction.EXPORT, exportSeveralReason) { transferUi.exportMany(chosen) }
                }
            },
        )
    }

    if (reordering) {
        ReorderServersDialog(fleet) { reordering = false }
    }

    connectionFor?.let { deployment ->
        ServerSettingsDialog(deployment, fleet, secrets, store) { connectionFor = null }
    }

    accessFor?.let { deployment ->
        ServerAccessDialog(
            deployment = deployment,
            secrets = secrets,
            onCredentialsChanged = { fleet.reload() },
            onClose = { accessFor = null },
        )
    }

    ServerTransferDialogs(transferUi)
}

@Composable
private fun ServerCard(
    deployment: Deployment,
    metrics: FleetMetrics,
    onWake: () -> Unit,
    wakeAfter: Int,
    style: MetricsIndicatorStyle,
    onOpen: () -> Unit,
    compact: Boolean,
    onSize: (ServerCardSize?) -> Unit,
    onIndicator: (MetricsIndicatorStyle?) -> Unit,
    onTint: (String?) -> Unit,
    onForget: () -> Unit,
    onExport: () -> Unit,
    onConnection: () -> Unit,
    onAccess: () -> Unit,
    modifier: Modifier = Modifier
) {
    var menu by remember { mutableStateOf(false) }
    Box(modifier) {
        Column(
            Modifier
                .fillMaxHeight()
                .cardSurface(
                    Gryonix.colors.cardBackground,
                    tint = ServerTint.of(deployment.tintName).composeColor(),
                )
                .combinedClickable(
                    onClick = onOpen,
                    onLongClick = { menu = true }
                )
        ) {
        Row(Modifier.fillMaxHeight()) {
            Column(Modifier.weight(1f).padding(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        deployment.name,
                        style = MaterialTheme.typography.titleLarge,
                        color = Gryonix.colors.label,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f)
                    )
                    IconButton(onClick = { menu = true }, modifier = Modifier.size(28.dp)) {
                        Icon(
                            Icons.Filled.MoreVert,
                            contentDescription = stringResource(R.string.card_menu),
                            tint = Gryonix.colors.tertiaryLabel,
                            modifier = Modifier.size(20.dp),
                        )
                    }
                }
                Text(
                    deployment.domain.ifEmpty { deployment.entry.host },
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.secondaryLabel,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                if (!compact) {
                    Text(
                        "${deployment.entry.user}@${deployment.entry.host}:${deployment.entry.port}",
                        style = MaterialTheme.typography.bodySmall,
                        color = Gryonix.colors.tertiaryLabel,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                val readings by metrics.card(deployment.id).collectAsState()
                CardReadings(deployment, readings, style = style, compact = compact, onWake = onWake, wakeAfter = wakeAfter)

                val services = deployment.services.size
                val machines = deployment.nodes.size
                Text(
                    pluralStringResource(R.plurals.services_count, services, services) +
                        if (machines > 1) {
                            "  ·  " + pluralStringResource(R.plurals.machines_count, machines, machines)
                        } else "",
                    style = MaterialTheme.typography.labelMedium,
                    color = Gryonix.colors.tertiaryLabel,
                )
            }
        }
        }
        ServerCardMenu(
            expanded = menu,
            name = deployment.name,
            size = deployment.cardSize,
            style = deployment.metricsIndicatorStyle,
            tint = deployment.tintName,
            onDismiss = { menu = false },
            onSize = onSize,
            onIndicator = onIndicator,
            onTint = onTint,
            onForget = onForget,
            onExport = onExport,
            onConnection = onConnection,
            onAccess = onAccess,
        )
    }
}

/** The machines of one card, each with its own readings */
@Composable
private fun CardReadings(
    deployment: Deployment,
    readings: Map<SSHHostID, HostMetricsState>,
    style: MetricsIndicatorStyle,
    compact: Boolean,
    onWake: () -> Unit,
    wakeAfter: Int,
) {
    val machines = deployment.nodes
    val wakeNode = WakeOnLANViewModel.homeMachine(deployment)
    val wakeTarget = wakeNode?.sshHost
    val onNetwork by produceState<Boolean?>(null, deployment.id, wakeNode) {
        while (wakeNode != null) {
            value = LocalNetworkCheck.isOnNetwork(wakeNode, deployment.wakeOnLANBroadcast)
            delay(10_000)
        }
    }
    machines.forEach { node ->
        if (machines.size > 1) {
            Text(
                node.name.ifEmpty { node.endpoint.host },
                style = MaterialTheme.typography.labelSmall,
                color = Gryonix.colors.secondaryLabel,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        MetricsBlock(
            state = readings[node.sshHost] ?: HostMetricsState(),
            style = style,
            detailed = !compact,
            compact = compact,
            onWake = onWake.takeIf { node.sshHost == wakeTarget },
            wakeGate = WakeGate(wakeAfter, onNetwork),
        )
    }
}

@Composable
private fun EmptyFleet() {
    Column(
        modifier = Modifier.fillMaxSize().padding(32.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            stringResource(R.string.no_servers),
            style = MaterialTheme.typography.headlineSmall,
            color = Gryonix.colors.label,
        )
        Text(
            stringResource(R.string.no_servers_hint),
            style = MaterialTheme.typography.bodyMedium
        )
    }
}
