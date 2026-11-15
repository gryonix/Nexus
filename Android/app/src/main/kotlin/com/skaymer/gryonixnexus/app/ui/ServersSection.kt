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
import com.skaymer.gryonixnexus.app.ui.design.PullToRefresh
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.cardSurface
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.security.GatedAction
import com.skaymer.gryonixnexus.app.security.rememberGuard
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.app.servers.DemoDeployments
import com.skaymer.gryonixnexus.app.servers.DeploymentTransferService
import com.skaymer.gryonixnexus.app.servers.FleetMetrics
import com.skaymer.gryonixnexus.servercontrol.ServerListOrdering
import com.skaymer.gryonixnexus.servercontrol.ServerProblem
import com.skaymer.gryonixnexus.servercontrol.ServerProblems
import androidx.compose.runtime.saveable.rememberSaveable
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
    onlyServerOpened: () -> Boolean = { true },
    markOnlyServerOpened: () -> Unit = {},
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
    var choosingForQr by remember { mutableStateOf(false) }
    var quickSending by remember { mutableStateOf<List<Deployment>?>(null) }
    var quickReceiving by remember { mutableStateOf(false) }
    var askingImportWay by remember { mutableStateOf(false) }
    var askingExportWay by remember { mutableStateOf(false) }

    val transferUi = rememberServerTransfer(
        transfer,
        known = { fleet.deployments.value },
        onImported = { fleet.reload() },
        onGroups = fleet::adoptGroupOrder,
    )
    val offline by metrics.offline.collectAsState()
    var problemFilter by remember { mutableStateOf<ServerProblem?>(null) }
    val context = androidx.compose.ui.platform.LocalContext.current
    val facts = remember(deployments, offline) { healthFacts(context, deployments, metrics, offline) }
    val inGroup = remember(deployments, group) {
        group?.let { name -> ServerGroups.members(name, deployments) } ?: deployments
    }
    val groupFacts = remember(inGroup, facts) {
        val ids = inGroup.map { it.id }.toSet()
        facts.filter { it.id in ids }
    }
    val settingsRevision by store.revision.collectAsState()
    val showSummary = remember(settingsRevision) { store.boolean(PROBLEM_SUMMARY_KEY) ?: true }
    val summaryTiles = remember(settingsRevision) { visibleProblemTiles(store.string(PROBLEM_SUMMARY_HIDDEN_KEY)) }
    val shown = remember(inGroup, offline, problemFilter, facts) {
        val wanted = problemFilter?.let { ServerProblems.ids(it, facts) }
        val filtered = if (wanted == null) inGroup else inGroup.filter { it.id in wanted }
        ServerListOrdering.ordered(filtered) { it.id in offline }
    }
    LaunchedEffect(deployments.size) {
        if (!onlyServerOpened() && deployments.size == 1) {
            markOnlyServerOpened()
            onOpen(deployments.first().id)
        }
    }
    val rows = remember(shown, fallback) { ServerCardLayout.rows(shown, fallback) }

    SideEffect { bar.count = deployments.size }
    LaunchedEffect(bar.pending) {
        when (bar.pending) {
            FleetBarCommands.Command.ADD_SERVER -> onAddServer()
            FleetBarCommands.Command.IMPORT -> askingImportWay = true
            FleetBarCommands.Command.EXPORT_SEVERAL -> askingExportWay = true
            FleetBarCommands.Command.REORDER -> reordering = true
            null -> Unit
        }
        if (bar.pending != null) bar.taken()
    }

    if (quickReceiving) {
        QuickTransferReceiveSheet(deliver = transferUi::offerAll) {
            quickReceiving = false
            transferUi.askNextReplacement()
        }
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
            onExportGroups = { groups ->
                guard(GatedAction.EXPORT, exportSeveralReason) {
                    val members = ServerGroups.membersOfAny(groups, deployments)
                        .filterNot { DemoDeployments.isDemoID(it.id) }
                    if (members.isNotEmpty()) transferUi.exportGroups(groups, members)
                }
            },
            onImport = { askingImportWay = true },
        )
        PullToRefresh(onRefresh = {
            fleet.reload()
            metrics.reconnectAll(fleet.deployments.value)
        }) {
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(horizontal = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 12.dp)
        ) {
            item(key = "problem-cards") {
                if (showSummary) {
                    ServerProblemCards(ServerProblems.counts(groupFacts), summaryTiles, problemFilter) { problemFilter = it }
                }
                problemFilter?.let { chosen ->
                    val title = stringResource(title(chosen))
                    AiExplainButton(context = {
                        com.skaymer.gryonixnexus.app.ai.AiExplain.problem(chosen, facts, fleet.deployments.value, title)
                    })
                }
            }
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
                            onIcon = { fleet.setIcon(deployment.id, it) },
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
    }

    warning?.let { deployment ->
        TransferWayAlert(
            title = stringResource(R.string.export_server),
            message = stringResource(R.string.export_server_warning),
            destructive = true,
            onFile = {
                warning = null
                transferUi.exportOne(deployment)
            },
            onQr = {
                warning = null
                guard(GatedAction.EXPORT, exportSeveralReason) { quickSending = listOf(deployment) }
            },
            onCancel = { warning = null },
        )
    }

    if (askingImportWay) {
        TransferWayAlert(
            title = stringResource(R.string.transfer_import),
            onFile = {
                askingImportWay = false
                transferUi.import()
            },
            onQr = {
                askingImportWay = false
                quickReceiving = true
            },
            onCancel = { askingImportWay = false },
        )
    }

    if (askingExportWay) {
        TransferWayAlert(
            title = stringResource(R.string.transfer_export),
            onFile = {
                askingExportWay = false
                choosingExports = true
            },
            onQr = {
                askingExportWay = false
                if (deployments.size == 1) {
                    guard(GatedAction.EXPORT, exportSeveralReason) { quickSending = deployments }
                } else {
                    choosingForQr = true
                }
            },
            onCancel = { askingExportWay = false },
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

    QuickTransferSendDialogs(
        deployments = deployments,
        transfer = transfer,
        choosing = choosingForQr,
        sending = quickSending,
        onChosen = { chosen ->
            choosingForQr = false
            if (chosen.isNotEmpty()) guard(GatedAction.EXPORT, exportSeveralReason) { quickSending = chosen }
        },
        onClose = {
            choosingForQr = false
            quickSending = null
        },
    )

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
    onIcon: (String?) -> Unit,
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
            val readings by metrics.card(deployment.id).collectAsState()
            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                CardReadings(deployment, readings, style = style, compact = compact, onWake = onWake, wakeAfter = wakeAfter)
            }
        }
        ServerCardMenu(
            expanded = menu,
            name = deployment.name,
            size = deployment.cardSize,
            style = deployment.metricsIndicatorStyle,
            tint = deployment.tintName,
            icon = deployment.iconSymbol,
            onDismiss = { menu = false },
            onSize = onSize,
            onIndicator = onIndicator,
            onTint = onTint,
            onIcon = onIcon,
            deployment = deployment,
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
    val tint = ServerTint.of(deployment.tintName).composeColor() ?: Gryonix.colors.accent
    if (machines.size > 1) {
        CombinedCardHeader(deployment, readings[machines.first().sshHost]?.snapshot?.osID, tint)
    }
    machines.forEachIndexed { index, node ->
        if (index > 0) MachineDivider()
        val state = readings[node.sshHost] ?: HostMetricsState()
        val block: @Composable (Boolean) -> Unit = { gaugesOnly ->
            MetricsBlock(
                state = state,
                style = style,
                detailed = false,
                compact = compact,
                onWake = onWake.takeIf { node.sshHost == wakeTarget },
                wakeGate = WakeGate(wakeAfter, onNetwork),
            )
        }
        MachineCardBlock(
            deployment = deployment,
            host = node.sshHost,
            state = state,
            tint = tint,
            embedded = machines.size > 1,
            compact = compact,
            otherGauges = if (style == MetricsIndicatorStyle.BARS) null else ({ block(true) }),
            offline = { block(false) },
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

/** Import and export offer a file or a QR code */
@Composable
private fun TransferWayAlert(
    title: String,
    onFile: () -> Unit,
    onQr: () -> Unit,
    onCancel: () -> Unit,
    message: String? = null,
    destructive: Boolean = false,
) {
    IOSAlert(
        title = title,
        message = message,
        onDismiss = onCancel,
        actions = listOf(
            AlertAction(stringResource(R.string.transfer_way_file), destructive = destructive, onSelect = onFile),
            AlertAction(stringResource(R.string.transfer_way_qr), destructive = destructive, onSelect = onQr),
            AlertAction(stringResource(R.string.group_cancel), onSelect = onCancel),
        ),
    )
}
