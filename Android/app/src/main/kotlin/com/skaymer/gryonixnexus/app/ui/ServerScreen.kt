package com.skaymer.gryonixnexus.app.ui

import com.skaymer.gryonixnexus.app.servers.AddedServiceScripts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.ui.unit.IntOffset
import kotlinx.coroutines.delay
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.MoreVert
import com.skaymer.gryonixnexus.app.terminal.TerminalSessions
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.IconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.InfoNoteButton
import com.skaymer.gryonixnexus.app.terminal.ShellUserViewModel
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Alignment
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.shell.AppTab
import com.skaymer.gryonixnexus.app.shell.AppNavigator
import com.skaymer.gryonixnexus.app.configurator.of
import com.skaymer.gryonixnexus.app.configurator.ConfiguratorViewModel
import com.skaymer.gryonixnexus.app.configurator.ConfiguratorForm
import com.skaymer.gryonixnexus.app.mesh.MeshViewModel
import com.skaymer.gryonixnexus.app.servers.BackupsViewModel
import com.skaymer.gryonixnexus.app.servers.RelayStatusViewModel
import com.skaymer.gryonixnexus.app.servers.ServiceAddress
import com.skaymer.gryonixnexus.app.servers.ServiceControlViewModel
import com.skaymer.gryonixnexus.app.servers.VaultwardenTwoFactorViewModel
import com.skaymer.gryonixnexus.app.servers.ServiceState
import com.skaymer.gryonixnexus.app.servers.UpdatesViewModel
import com.skaymer.gryonixnexus.app.servers.containersNeedingAttention
import com.skaymer.gryonixnexus.app.servers.HostMetricsState
import com.skaymer.gryonixnexus.app.session.ConnectionCheck
import com.skaymer.gryonixnexus.app.containers.ContainersViewModel
import com.skaymer.gryonixnexus.app.files.FileBrowserViewModel
import com.skaymer.gryonixnexus.app.logs.ServiceLogsViewModel
import com.skaymer.gryonixnexus.app.dns.DKIMViewModel
import com.skaymer.gryonixnexus.app.dns.DynamicDNSViewModel
import com.skaymer.gryonixnexus.app.hosts.HostProbeState
import com.skaymer.gryonixnexus.app.hosts.HostProbesViewModel
import com.skaymer.gryonixnexus.app.security.SecurityViewModel
import com.skaymer.gryonixnexus.agentcontrol.AgentModOperations
import com.skaymer.gryonixnexus.app.ai.LocalModelsViewModel
import com.skaymer.gryonixnexus.app.ai.ModelKeysViewModel
import com.skaymer.gryonixnexus.app.servers.ModsViewModel
import gryonixnexusd.v1.ModSlot
import com.skaymer.gryonixnexus.app.mail.MailboxesViewModel
import com.skaymer.gryonixnexus.app.security.GatedAction
import com.skaymer.gryonixnexus.app.security.rememberGuard
import com.skaymer.gryonixnexus.app.servers.AddMachineViewModel
import com.skaymer.gryonixnexus.app.servers.AddServiceViewModel
import com.skaymer.gryonixnexus.app.servers.ServiceRemovalViewModel
import com.skaymer.gryonixnexus.app.metrics.HistoryPresentation
import com.skaymer.gryonixnexus.app.metrics.HistoryViewModel
import com.skaymer.gryonixnexus.app.metrics.MetricsBoardViewModel
import com.skaymer.gryonixnexus.app.metrics.MetricPanelStore
import com.skaymer.gryonixnexus.app.servers.FleetRepository
import com.skaymer.gryonixnexus.app.servers.HostActionsViewModel
import com.skaymer.gryonixnexus.app.shell.DisplaySettings
import com.skaymer.gryonixnexus.app.shell.ServerSection
import com.skaymer.gryonixnexus.app.shell.ServerSectionSettings
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.app.vpn.VPNClientsViewModel
import com.skaymer.gryonixnexus.app.vpn.VpnTunnel
import com.skaymer.gryonixnexus.agentcontrol.VPNClientProtocols
import com.skaymer.gryonixnexus.app.agent.AgentInstallViewModel
import com.skaymer.gryonixnexus.app.agent.AgentSelfUpdateViewModel
import com.skaymer.gryonixnexus.app.secrets.CloudflareTokenStore
import com.skaymer.gryonixnexus.app.shell.TabBarSettings
import kotlinx.coroutines.launch
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.placing
import com.skaymer.gryonixnexus.servercontrol.removingNode
import com.skaymer.gryonixnexus.servercontrol.MetricsIndicatorStyle
import com.skaymer.gryonixnexus.app.access.AccessViewModel
import com.skaymer.gryonixnexus.app.devices.DevicesViewModel
import com.skaymer.gryonixnexus.app.servers.EraseViewModel
import com.skaymer.gryonixnexus.servercontrol.HealthLevel
import com.skaymer.gryonixnexus.servercontrol.ServicePowerAction

/** One server, from what is already known about it */
@Composable
fun ServerScreen(
    deployment: Deployment,
    tabs: TabBarSettings,
    check: ConnectionCheck,
    services: ServiceControlViewModel,
    updates: UpdatesViewModel,
    backups: BackupsViewModel,
    mesh: MeshViewModel,
    access: AccessViewModel,
    devices: DevicesViewModel,
    erase: EraseViewModel,
    sections: ServerSectionSettings,
    store: SettingsStore,
    fleet: FleetRepository,
    history: HistoryViewModel,
    containers: ContainersViewModel,
    vpnClients: VPNClientsViewModel,
    /** The tunnel this device brings up itself — see `VpnTunnel` */
    vpnTunnel: VpnTunnel,
    hostActions: HostActionsViewModel,
    wakeOnLAN: com.skaymer.gryonixnexus.app.servers.WakeOnLANViewModel,
    files: FileBrowserViewModel,
    logs: ServiceLogsViewModel,
    removal: ServiceRemovalViewModel,
    adding: AddServiceViewModel,
    mailboxes: MailboxesViewModel,
    modelKeys: ModelKeysViewModel,
    localModels: LocalModelsViewModel,
    mods: ModsViewModel,
    dns: DynamicDNSViewModel,
    /** The host's CrowdSec defence and what it caught — see `SecurityCard` */
    security: SecurityViewModel,
    /** Each machine's own tunnel, memory and volumes — see `HostCard` */
    hostProbes: HostProbesViewModel,
    machines: AddMachineViewModel,
    dkim: DKIMViewModel,
    configurator: ConfiguratorViewModel,
    navigator: AppNavigator,
    terminals: TerminalSessions,
    pushed: PushedScreen,
    /** Putting the control-plane agent on this server — see `AgentCard` */
    agentInstall: AgentInstallViewModel,
    agentSelfUpdate: AgentSelfUpdateViewModel,
    board: MetricsBoardViewModel,
    panels: MetricPanelStore,
    /** Whether a Cloudflare tunnel can be minted — see `CloudflareTokenStore` */
    cloudflare: CloudflareTokenStore,
    /** The relay path's three rows, on a scenario B server */
    relay: RelayStatusViewModel,
    /** Moving a service to another machine */
    moves: com.skaymer.gryonixnexus.app.servers.ServiceMoveViewModel,
    /** Making an account to open a shell with — see `CreateShellUserSheet` */
    shellUsers: ShellUserViewModel? = null,
    /** Taking the agent off this server */
    agentRemoval: com.skaymer.gryonixnexus.app.agent.AgentRemoval? = null,
    /** The server's own packages — see `SystemUpdateDialog` */
    systemUpdates: com.skaymer.gryonixnexus.app.servers.SystemUpdateViewModel? = null,
) {
    val context = remember(deployment) { deployment.serviceContext }
    var showingConfiguration by rememberSaveable(deployment.id) { mutableStateOf(false) }
    val groupOverride by tabs.groupServicesOverride.collectAsState()
    val grouped = remember(deployment, groupOverride) { tabs.groupsServices(deployment.services) }
    val shelves = remember(deployment) { shelves(deployment.services) }
    val flat = remember(deployment) { deployment.services.toList() }

    LaunchedEffect(deployment.id) { services.refresh(deployment) }
    LaunchedEffect(deployment.id) { agentSelfUpdate.load(deployment) }
    LaunchedEffect(deployment.id) { moves.refreshInterrupted(deployment.id) }
    val appContext = androidx.compose.ui.platform.LocalContext.current.applicationContext
    LaunchedEffect(deployment.id) { (appContext as? com.skaymer.gryonixnexus.app.GryonixApplication)?.notify?.sync(deployment) }
    DisposableEffect(deployment.id) { onDispose { services.stop() } }
    val serviceStates by services.states.collectAsState()

    DisposableEffect(deployment.id) { onDispose { updates.reset() } }
    var showingUpdates by rememberSaveable(deployment.id) { mutableStateOf(false) }
    var showingSystemUpdate by rememberSaveable(deployment.id) { mutableStateOf(false) }
    var choosingInstall by remember(deployment.id) {
        mutableStateOf<Triple<List<com.skaymer.gryonixnexus.catalog.ManagedService>, String?, List<com.skaymer.gryonixnexus.core.Artifact>>?>(null)
    }
    var rerunning by remember(deployment.id) {
        mutableStateOf<Pair<Boolean, List<com.skaymer.gryonixnexus.core.Artifact>>?>(null)
    }
    DisposableEffect(deployment.id) { onDispose { backups.reset() } }
    var showingBackups by rememberSaveable(deployment.id) { mutableStateOf(false) }
    DisposableEffect(deployment.id) { onDispose { mesh.reset() } }
    var showingMesh by rememberSaveable(deployment.id) { mutableStateOf(false) }
    DisposableEffect(deployment.id) { onDispose { access.reset() } }
    var showingAccess by rememberSaveable(deployment.id) { mutableStateOf(false) }
    var showingDevices by rememberSaveable(deployment.id) { mutableStateOf(false) }
    var showingErase by rememberSaveable(deployment.id) { mutableStateOf(false) }
    var arranging by rememberSaveable(deployment.id) { mutableStateOf(false) }
    var logsService by rememberSaveable(deployment.id) { mutableStateOf<String?>(null) }
    var addingService by rememberSaveable(deployment.id) { mutableStateOf(false) }
    var showingMailboxes by rememberSaveable(deployment.id) { mutableStateOf(false) }
    var showingModelKeys by rememberSaveable(deployment.id) { mutableStateOf(false) }
    var showingLocalModels by rememberSaveable(deployment.id) { mutableStateOf(false) }
    var showingMods by rememberSaveable(deployment.id) { mutableStateOf(false) }
    var showingDDNS by rememberSaveable(deployment.id) { mutableStateOf(false) }
    var showingNotify by rememberSaveable(deployment.id) { mutableStateOf(false) }
    var showingDKIM by rememberSaveable(deployment.id) { mutableStateOf(false) }
    var addingMachine by rememberSaveable(deployment.id) { mutableStateOf(false) }
    var exploringHost by remember(deployment.id) { mutableStateOf<SSHHostID?>(null) }
    var energyHost by remember(deployment.id) { mutableStateOf<SSHHostID?>(null) }
    var storageHost by remember(deployment.id) { mutableStateOf<SSHHostID?>(null) }
    var cacheHost by remember(deployment.id) { mutableStateOf<SSHHostID?>(null) }
    var speedHost by remember(deployment.id) { mutableStateOf<SSHHostID?>(null) }
    var processesHost by remember(deployment.id) { mutableStateOf<SSHHostID?>(null) }
    var removingMachine by rememberSaveable(deployment.id) { mutableStateOf<String?>(null) }
    var machineError by remember(deployment.id) { mutableStateOf<String?>(null) }
    var removingService by rememberSaveable(deployment.id) { mutableStateOf<String?>(null) }
    val hostActionsState by hostActions.state.collectAsState()
    val guard = rememberGuard()
    DisposableEffect(deployment.id) { onDispose { hostActions.reset() } }

    val settingsRevision by store.revision.collectAsState()

    val historyInline = remember(settingsRevision) {
        HistoryPresentation.inline(store.boolean(HistoryPresentation.INLINE_KEY))
    }

    val available = remember(deployment, settingsRevision) {
        ServerSectionSettings.available(
            metrics = DisplaySettings.metrics(store.string(DisplaySettings.METRICS_PLACEMENT_KEY)),
            containers = DisplaySettings.containers(store.string(DisplaySettings.CONTAINERS_PLACEMENT_KEY)),
            vpn = DisplaySettings.vpn(store.string(DisplaySettings.VPN_PLACEMENT_KEY)),
            canListContainers = deployment.usesAgent,
            hasVPN = VPNClientProtocols.installed(deployment.services).isNotEmpty(),
        )
    }
    val order by sections.order.collectAsState()
    val hidden by sections.hidden.collectAsState()
    val ordered = remember(available, order, hidden, deployment.id) {
        sections.ordered(available, deployment.id)
    }
    var currentRaw by rememberSaveable(deployment.id) {
        mutableStateOf(sections.startSection(available, deployment.id).raw)
    }
    val current = ServerSection.of(currentRaw) ?: ServerSection.GENERAL
    val generalList = rememberLazyListState()
    val tourStep by AppTourFocus.step.collectAsState()
    LaunchedEffect(tourStep) {
        val section = tourStep?.section ?: return@LaunchedEffect
        if (section in ordered) currentRaw = section.raw
        when (tourStep) {
            AppTourStep.SECURITY -> revealSecurity(generalList)
            AppTourStep.SERVER_STRIP, AppTourStep.SITES -> {
                delay(300)
                generalList.animateScrollToItem(0)
            }
            else -> Unit
        }
    }
    LaunchedEffect(ordered, currentRaw) {
        val reachable = sections.reachable(current, available, deployment.id)
        if (reachable != current) currentRaw = reachable.raw
    }

    storageHost?.let { host ->
        BackHandler { storageHost = null }
        val title = stringResource(R.string.storage_disks_and_raid)
        DisposableEffect(title) {
            pushed.push(title) { storageHost = null }
            onDispose { pushed.clear() }
        }
        StorageScreen(server = deployment, host = host)
        return
    }

    cacheHost?.let { host ->
        BackHandler { cacheHost = null }
        val title = stringResource(R.string.cache_disk_title)
        DisposableEffect(title) {
            pushed.push(title) { cacheHost = null }
            onDispose { pushed.clear() }
        }
        CacheDiskScreen(server = deployment, host = host)
        return
    }

    processesHost?.let { host ->
        BackHandler { processesHost = null }
        val title = stringResource(R.string.processes_title)
        DisposableEffect(title) {
            pushed.push(title) { processesHost = null }
            onDispose { pushed.clear() }
        }
        TopProcessesScreen(server = deployment, host = host)
        return
    }

    speedHost?.let { host ->
        BackHandler { speedHost = null }
        val title = stringResource(R.string.speed_title)
        DisposableEffect(title) {
            pushed.push(title) { speedHost = null }
            onDispose { pushed.clear() }
        }
        SpeedTestScreen(server = deployment, host = host)
        return
    }

    energyHost?.let { host ->
        BackHandler { energyHost = null }
        val title = stringResource(R.string.energy_title)
        DisposableEffect(title) {
            pushed.push(title) { energyHost = null }
            onDispose { pushed.clear() }
        }
        EnergyScreen(history = history, server = deployment, host = host)
        return
    }

    exploringHost?.let { host ->
        BackHandler { exploringHost = null }
        val machine = deployment.nodes.firstOrNull { it.sshHost == host }
        val barTitle = machine?.name?.ifEmpty { machine.endpoint.host } ?: deployment.name
        DisposableEffect(barTitle) {
            pushed.push(barTitle) { exploringHost = null }
            onDispose { pushed.clear() }
        }
        HistoryExplorer(
            fleet = fleet,
            history = history,
            initialServerID = deployment.id,
            initialHost = host,
        )
        return
    }

    Column(Modifier.fillMaxSize()) {
        Box(Modifier.appTourTarget(AppTourTarget.SERVER_STRIP)) {
            ServerSectionsStrip(
                sections = ordered,
                available = available,
                current = current,
                settings = sections,
                deploymentID = deployment.id,
                onSelect = { currentRaw = it.raw },
                onArrange = { arranging = true },
            )
        }

        Box(Modifier.fillMaxSize().sectionSwipe(ordered, current) { currentRaw = it.raw }) {
        AnimatedContent(
            targetState = current,
            transitionSpec = { sectionSlide(ordered.indexOf(targetState) >= ordered.indexOf(initialState)) },
            label = "section",
        ) { current ->
        when (current) {
            ServerSection.GENERAL -> LazyColumn(
                state = generalList,
                modifier = Modifier.fillMaxSize(),
                contentPadding = GroupedContentPadding,
                verticalArrangement = GroupedSpacing,
            ) {
                item { ConnectionRow(deployment, check) }
                item { RelayStatusCard(deployment, relay) }
                item { Box(Modifier.appTourTarget(AppTourTarget.SERVER_SITES)) { SitesCard(deployment, tabs) } }

                item {
                    val rows = buildList<@Composable (Boolean) -> Unit> {
                        add { divider ->
                            AccessCard(
                                onOpen = {
                                    guard(GatedAction.ACCESS_SCREEN, deployment.name) {
                                        showingAccess = true
                                    }
                                },
                                showDivider = divider,
                            )
                        }
                        if (deployment.usesAgent) {
                            add { divider ->
                                DevicesCard(
                                    onOpen = {
                                        guard(GatedAction.ACCESS_SCREEN, deployment.name) {
                                            showingDevices = true
                                        }
                                    },
                                    showDivider = divider,
                                )
                            }
                        }
                        if (systemUpdates != null) {
                            add { divider -> SystemUpdateCard({ showingSystemUpdate = true }, divider) }
                        }
                        add { divider ->
                            UpdatesCard(deployment, updates, { showingUpdates = true }, divider)
                        }
                        if (MailboxesViewModel.hasEngine(deployment)) {
                            add { divider -> MailboxesCard({ showingMailboxes = true }, divider) }
                        }
                        if (ModelKeysViewModel.canManage(deployment)) {
                            add { divider -> ModelKeysCard({ showingModelKeys = true }, divider) }
                        }
                        if (canToggleVaultwardenSignups(deployment)) {
                            add { divider ->
                                VaultwardenSignupsCard(deployment, { open ->
                                    val settings = deployment.serviceSettings.copy(vaultwardenAllowSignups = open)
                                    ServiceRegistry.service(ServiceID.VAULTWARDEN)?.let {
                                        adding.reapply(deployment.copy(serviceSettings = settings), it)
                                    }
                                }, divider)
                            }
                        }
                        if (VaultwardenTwoFactorViewModel.canShow(deployment)) {
                            add { divider -> VaultwardenTwoFactorCard(deployment, divider) }
                        }
                        if (LocalModelsViewModel.canManage(deployment)) {
                            add { divider -> LocalModelsCard({ showingLocalModels = true }, divider) }
                        }
                        if (ModsViewModel.canManage(deployment)) {
                            add { divider ->
                                ModsCard(
                                    callsThemPlugins = AgentModOperations.slot(deployment.serviceSettings.minecraftJavaFlavour) == ModSlot.MOD_SLOT_PLUGINS,
                                    onOpen = { showingMods = true },
                                    showDivider = divider,
                                )
                            }
                        }
                        if (DKIMViewModel.hasMailEngine(deployment)) {
                            add { divider -> DKIMCard({ showingDKIM = true }, divider) }
                        }
                        if (DynamicDNSViewModel.canManage(deployment)) {
                            add { divider -> DynamicDNSCard({ showingDDNS = true }, divider) }
                        }
                        if (com.skaymer.gryonixnexus.app.notify.NotifyViewModel.canManage(deployment)) {
                            add { divider -> NotificationsCard({ showingNotify = true }, divider) }
                        }
                        if (BackupsViewModel.backupCapableServices(deployment).isNotEmpty()) {
                            add { divider ->
                                BackupsCard(deployment, backups, { showingBackups = true }, divider)
                            }
                        }
                        if (MeshViewModel.managesMesh(deployment, agentTransportAvailable = true)) {
                            add { divider -> MeshCard(mesh, { showingMesh = true }, divider) }
                        }
                    }
                    GroupedSection {
                        rows.forEachIndexed { index, row -> row(index != rows.lastIndex) }
                    }
                }

                item {
                    StorageCard(
                        deployment = deployment,
                        onOpenStorage = { storageHost = it },
                        onOpenCache = { cacheHost = it },
                    )
                }

                if (SecurityViewModel.canShow(deployment, agentTransportAvailable = true)) {
                    item {
                        Box(Modifier.appTourTarget(AppTourTarget.SERVER_SECURITY)) {
                            SecurityCard(deployment, security, store)
                        }
                    }
                }

                item {
                    val probes by hostProbes.state.collectAsState()
                    LaunchedEffect(deployment.id) {
                        hostProbes.reset()
                        hostProbes.load(deployment)
                    }
                    Column(verticalArrangement = GroupedSpacing) {
                        deployment.nodes.forEach { node ->
                            HostCard(
                                title = node.name.ifEmpty { node.endpoint.host },
                                state = probes[node.sshHost] ?: HostProbeState(),
                                onOpenHistory = if (historyInline) null else {
                                    { exploringHost = node.sshHost }
                                },
                                onOpenEnergy = { energyHost = node.sshHost },
                                onOpenSpeed = { speedHost = node.sshHost },
                                onOpenProcesses = { processesHost = node.sshHost },
                                inlineHistory = if (!historyInline) null else {
                                    {
                                        InlineHistory(
                                            history = history,
                                            server = deployment,
                                            host = node.sshHost,
                                        )
                                    }
                                },
                            )
                        }
                    }
                }

                item {
                    GroupedSection(header = stringResource(R.string.machines)) {
                        deployment.nodes.forEach { node ->
                            GroupedRow(
                                trailing = {
                                    if (deployment.isMultiHost) {
                                        IconButton(
                                            onClick = { removingMachine = node.id },
                                            modifier = Modifier.size(28.dp),
                                        ) {
                                            Icon(
                                                Icons.Filled.Close,
                                                contentDescription =
                                                    stringResource(R.string.machines_remove),
                                                tint = Gryonix.colors.danger,
                                                modifier = Modifier.size(18.dp),
                                            )
                                        }
                                    }
                                },
                            ) {
                                RowLabel(
                                    title = node.name.ifEmpty { node.endpoint.host },
                                    subtitle = "${node.endpoint.user}@${node.endpoint.host}:" +
                                        "${node.endpoint.port}  ·  " +
                                        node.capabilities.joinToString(", ") {
                                            it.name.lowercase()
                                        },
                                )
                            }
                        }
                        ActionRow(
                            text = stringResource(R.string.machines_add_title),
                            onClick = { addingMachine = true },
                            showDivider = false,
                        )
                    }
                }
                machineError?.let { message ->
                    item {
                        Text(
                            message,
                            style = MaterialTheme.typography.bodySmall,
                            color = Gryonix.colors.danger,
                            modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
                        )
                    }
                }

                item {
                    GroupedSection {
                        ActionRow(
                            text = stringResource(R.string.configuration_open),
                            onClick = { showingConfiguration = true },
                        )
                        if (deployment.usesAgent) {
                            ActionRow(
                                text = stringResource(R.string.repair_server),
                                onClick = { rerunning = true to AddedServiceScripts.scripts(ServiceRegistry.services(deployment.services), deployment) },
                            )
                        }
                        ActionRow(
                            text = stringResource(R.string.reinstall_server),
                            onClick = {
                                if (deployment.usesAgent) {
                                    rerunning = false to AddedServiceScripts.scripts(ServiceRegistry.services(deployment.services), deployment)
                                } else {
                                    configurator.adopt(ConfiguratorForm.of(deployment), deployment)
                                    navigator.show(AppTab.CONFIGURATOR)
                                }
                            },
                            showDivider = false,
                            trailing = {
                                InfoNoteButton(
                                    title = stringResource(R.string.reinstall_server),
                                    note = stringResource(R.string.reinstall_server_hint),
                                )
                            },
                        )
                    }
                }

                item {
                    AgentCard(deployment, agentInstall, onInstalled = { fleet.reload() }, removal = agentRemoval)
                }
                item {
                    AgentSelfUpdateCard(deployment, agentSelfUpdate)
                }

                item { HostActionsCard(deployment, hostActions, wakeOnLAN) }

                item { EraseCard { showingErase = true } }
            }

            ServerSection.APPS -> LazyColumn(
                modifier = Modifier.fillMaxSize().appTourTarget(AppTourTarget.SERVER_APPS),
                contentPadding = GroupedContentPadding,
                verticalArrangement = GroupedSpacing,
            ) {
                item { InterruptedMove(deployment, moves) }
                if (deployment.services.isEmpty()) {
                    item {
                        Text(
                            stringResource(R.string.no_services),
                            style = MaterialTheme.typography.bodyMedium,
                            color = Gryonix.colors.secondaryLabel,
                            modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
                        )
                    }
                } else if (grouped) {
                    shelves.forEach { (category, ids) ->
                        item(key = "shelf-${category.id}") {
                            Shelf(
                                category, ids, context, serviceStates, deployment, services,
                                onLogs = { logsService = it.rawValue },
                                onRemove = { removingService = it.rawValue },
                                onPlace = { service, node -> moves.request(deployment, service, node) },
                            )
                        }
                    }
                } else {
                    items(flat.size) { index ->
                        val id = flat[index]
                        ServiceRow(
                            id, context, serviceStates[id], deployment, services,
                            onLogs = { logsService = it.rawValue },
                            onRemove = { removingService = it.rawValue },
                            onPlace = { service, node -> moves.request(deployment, service, node) },
                        )
                    }
                }
                if (AddServiceViewModel.canAdd(deployment)) {
                    item {
                        GroupedSection {
                            ActionRow(
                                text = stringResource(R.string.add_service),
                                onClick = { addingService = true },
                                showDivider = false,
                            )
                        }
                    }
                }
            }

            ServerSection.METRICS -> Box(Modifier.appTourTarget(AppTourTarget.SERVER_METRICS)) {
                MetricsSection(fleet, history, board, panels, onlyServer = deployment)
            }
            ServerSection.CONTAINERS -> ContainersSection(fleet, containers, only = deployment.id)
            ServerSection.VPN ->
                VPNSection(fleet, vpnClients, only = deployment.id, tunnel = vpnTunnel,
                           onChangeRealitySite = adding::changeRealitySite,
                           onRenewRealityKey = adding::renewRealityKey)
            ServerSection.TERMINAL -> Column(
                Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground)
            ) {
                var shell by rememberSaveable(deployment.id) { mutableStateOf(false) }
                if (shell) {
                    TerminalSection(deployment, terminals, Modifier.weight(1f), shellUsers = shellUsers)
                    PlainButton(
                        text = stringResource(R.string.terminal_close),
                        onClick = { shell = false },
                        modifier = Modifier.padding(horizontal = 8.dp),
                    )
                } else {
                    Column(Modifier.padding(vertical = 16.dp)) {
                        GroupedSection {
                            ActionRow(
                                text = stringResource(R.string.terminal_open),
                                onClick = { shell = true },
                                showDivider = false,
                            )
                        }
                    }
                    Box(Modifier.weight(1f)) { FileBrowserSection(deployment, files) }
                }
            }
        }
        }
        }
    }

    if (showingUpdates) {
        UpdatesDialog(deployment, updates) { showingUpdates = false }
    }
    if (showingSystemUpdate && systemUpdates != null) {
        SystemUpdateDialog(deployment, systemUpdates) { showingSystemUpdate = false }
    }
    if (showingBackups) {
        BackupsDialog(deployment, backups, fleet.deployments.value) { showingBackups = false }
    }
    if (showingMesh) {
        MeshDialog(deployment, mesh) { showingMesh = false }
    }
    if (showingAccess) {
        AccessDialog(deployment, access) { showingAccess = false }
    }
    if (showingDevices) {
        DevicesDialog(deployment, devices) { showingDevices = false }
    }
    if (showingErase) {
        EraseDialog(deployment, erase) { showingErase = false }
    }
    if (showingConfiguration) {
        ConfigurationDialog(
            deployment = deployment,
            recorded = null,
            onClose = { showingConfiguration = false },
        )
    }
    if (arranging) {
        ServerSectionsDialog(sections, available, deployment.id) { arranging = false }
    }
    if (addingMachine) {
        AddMachineDialog(
            deployment = deployment,
            machines = machines,
            onCancel = { addingMachine = false },
            onAdded = { addingMachine = false },
        )
    }
    removingMachine?.let { id ->
        val node = deployment.nodes.firstOrNull { it.id == id }
        if (node == null) {
            removingMachine = null
        } else {
            ConfirmAlert(
                title = stringResource(R.string.machines_remove),
                message = node.name.ifEmpty { node.endpoint.host },
                confirm = stringResource(R.string.machines_remove),
                cancel = stringResource(R.string.containers_cancel),
                destructive = true,
                onConfirm = {
                    removingMachine = null
                    machineError = null
                    try {
                        fleet.update(deployment.removingNode(id))
                    } catch (refusal: Exception) {
                        machineError = refusal.message
                    }
                },
                onCancel = { removingMachine = null },
            )
        }
    }
    if (showingDKIM) {
        DKIMDialog(deployment, dkim) { showingDKIM = false }
    }
    if (showingDDNS) {
        DynamicDNSDialog(deployment, dns) { showingDDNS = false }
    }
    if (showingNotify) {
        NotificationsDialog(deployment) { showingNotify = false }
    }
    if (showingLocalModels) {
        LocalModelsDialog(deployment, localModels) { showingLocalModels = false }
    }
    if (showingMods) {
        ModsDialog(deployment, deployment.serviceSettings.minecraftJavaFlavour, mods) { showingMods = false }
    }
    if (showingModelKeys) {
        ModelKeysDialog(deployment, modelKeys) {
            showingModelKeys = false
            modelKeys.reset()
        }
    }
    if (showingMailboxes) {
        MailboxesDialog(deployment, mailboxes) { showingMailboxes = false }
    }
    if (addingService) {
        AddServiceDialog(
            deployment = deployment,
            canIssueTunnelToken = cloudflare.canIssueTunnelToken,
            onCancel = { addingService = false },
            onInstall = { ids, mount ->
                addingService = false
                val services = ServiceRegistry.services(ids.toSet())
                choosingInstall = Triple(services, mount, AddedServiceScripts.scripts(services, deployment))
            },
            loadArrays = {
                (appContext as? com.skaymer.gryonixnexus.app.GryonixApplication)?.storage?.dataArrays(deployment).orEmpty()
            },
            memoryBytes = (appContext as? com.skaymer.gryonixnexus.app.GryonixApplication)?.metrics
                ?.card(deployment.id)?.collectAsState()?.value?.get(deployment.servicesHost)?.snapshot?.memTotalBytes,
        )
    }
    rerunning?.let { (repair, scripts) ->
        InstallMethodSheet(
            services = ServiceRegistry.services(deployment.services),
            scripts = scripts,
            title = stringResource(if (repair) R.string.rerun_repair_title else R.string.rerun_reinstall_title),
            deviceText = stringResource(if (repair) R.string.rerun_repair_device else R.string.rerun_reinstall_device),
            onDevice = {
                rerunning = null
                adding.rerun(deployment, repair)
            },
            onCancel = { rerunning = null },
        )
    }
    choosingInstall?.let { (services, mount, scripts) ->
        InstallMethodSheet(
            services = services,
            scripts = scripts,
            onDevice = {
                choosingInstall = null
                adding.install(deployment, services, mount)
            },
            onCancel = { choosingInstall = null },
        )
    }
    AddServiceRunDialog(adding)
    removingService?.let { raw ->
        val service = ServiceRegistry.service(ServiceID(raw))
        if (service == null) {
            removingService = null
        } else {
            RemoveServiceDialog(
                deployment = deployment,
                service = service,
                lockdown = hostActionsState.lockdown.value,
                onCancel = { removingService = null },
                onConfirm = { purge ->
                    removingService = null
                    removal.remove(deployment, service, purge)
                },
            )
        }
    }
    RemoveServiceRunDialog(removal)
    ServiceMoveDialogs(moves)
    logsService?.let { raw ->
        val service = ServiceRegistry.service(ServiceID(raw))
        if (service == null) {
            logsService = null
        } else {
            ServiceLogsDialog(deployment, service, logs) { logsService = null }
        }
    }
    UpdateRunDialog(updates)
    BackupRunDialog(backups)
}

private fun shelves(services: Set<ServiceID>): List<Pair<ServiceCategory, List<ServiceID>>> {
    val byShelf = LinkedHashMap<ServiceCategory, MutableList<ServiceID>>()
    for (id in services) {
        val shelf = ServiceRegistry.service(id)?.displayCategory ?: continue
        byShelf.getOrPut(shelf) { mutableListOf() }.add(id)
    }
    return byShelf.entries.sortedBy { it.key }.map { it.key to it.value }
}

@Composable
private fun Shelf(
    category: ServiceCategory,
    ids: List<ServiceID>,
    context: com.skaymer.gryonixnexus.catalog.ServiceContext,
    states: Map<ServiceID, ServiceState>,
    deployment: Deployment,
    services: ServiceControlViewModel,
    onLogs: (ServiceID) -> Unit,
    onRemove: (ServiceID) -> Unit,
    onPlace: (ServiceID, String) -> Unit,
) {
    var expanded by rememberSaveable(category.id) { mutableStateOf(true) }
    Column {
        Row(
            Modifier
                .fillMaxWidth()
                .clickable { expanded = !expanded }
                .padding(
                    start = Metrics.listInset + 4.dp,
                    end = Metrics.listInset + 4.dp,
                    bottom = 6.dp,
                ),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                category.title.uppercase(),
                style = MaterialTheme.typography.bodySmall,
                color = Gryonix.colors.secondaryLabel,
                modifier = Modifier.weight(1f),
            )
            Icon(
                if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                contentDescription = null,
                tint = Gryonix.colors.accent,
                modifier = Modifier.size(20.dp),
            )
        }
        if (expanded) {
            GroupedSection(dividerInset = 46.dp) {
                ids.forEach {
                    ServiceRow(
                        it, context, states[it], deployment, services, onLogs, onRemove, onPlace,
                        showDivider = it != ids.last(),
                    )
                }
            }
        }
    }
}

@Composable
private fun ServiceRow(
    id: ServiceID,
    context: com.skaymer.gryonixnexus.catalog.ServiceContext,
    state: ServiceState?,
    deployment: Deployment,
    services: ServiceControlViewModel,
    onLogs: (ServiceID) -> Unit,
    onRemove: (ServiceID) -> Unit,
    onPlace: (ServiceID, String) -> Unit,
    showDivider: Boolean = true,
) {
    val service = ServiceRegistry.service(id)
    val workers = deployment.nodes.filter { it.runsServices }
    val runsOn = deployment.nodeRunning(id)
    GroupedRow(
        showDivider = showDivider,
        leading = { HealthDot(state) },
        trailing = {
            if (service != null) PowerMenu(
                busy = state?.isBusy == true,
                onAction = { services.power(deployment, id, it) },
                onRefresh = { services.refresh(deployment) },
                onLogs = { onLogs(id) },
                onRemove = { onRemove(id) },
                workers = if (workers.size > 1) workers else emptyList(),
                runsOn = runsOn?.id,
                onPlace = { node -> onPlace(id, node) },
            )
        },
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                service?.displayName ?: id.rawValue,
                style = MaterialTheme.typography.bodyLarge,
                color = Gryonix.colors.label,
            )
            val address = service?.let { ServiceAddress.of(it, context) }
            if (address != null) {
                Text(
                    address,
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.secondaryLabel,
                )
            }
            ServiceStatusLine(state)
        }
    }
}

/** Docker's own words, verbatim */
@Composable
private fun ServiceStatusLine(state: ServiceState?) {
    when {
        state == null || (!state.hasAnswered && !state.isBusy) -> Unit
        state.errorMessage != null && state.containers.isEmpty() -> Text(
            state.errorMessage!!,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.error
        )
        state.isBusy && state.containers.isEmpty() -> Text(
            stringResource(R.string.service_working),
            style = MaterialTheme.typography.bodySmall
        )
        state.containers.isEmpty() -> Text(
            stringResource(R.string.service_no_containers),
            style = MaterialTheme.typography.bodySmall
        )
        else -> Column {
            var expanded by rememberSaveable { mutableStateOf(false) }
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { expanded = !expanded },
            ) {
                Box(Modifier.weight(1f)) { ContainerHealthSummary(state) }
                Text(
                    if (expanded) "−" else "+",
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.secondaryLabel,
                )
            }
            if (expanded) {
                state.containers.forEach { container ->
                    Text(
                        "${container.name} · ${container.status}",
                        style = MaterialTheme.typography.bodySmall,
                        maxLines = 1
                    )
                }
            }
            state.errorMessage?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }
        }
    }
}

@Composable
private fun ContainerHealthSummary(state: ServiceState) {
    val unhealthy = state.containersNeedingAttention
    Text(
        if (unhealthy == 0) stringResource(R.string.service_all_healthy)
        else stringResource(R.string.service_need_attention, unhealthy),
        style = MaterialTheme.typography.bodySmall,
        color = if (unhealthy == 0) Color(0xFF34C759) else Color(0xFFFF9500),
    )
}

@Composable
private fun HealthDot(state: ServiceState?) {
    val worst = state?.containers?.map { it.health }?.maxByOrNull { level ->
        when (level) {
            HealthLevel.OK -> 0
            HealthLevel.UNKNOWN -> 1
            HealthLevel.WARNING -> 2
            HealthLevel.CRITICAL -> 3
        }
    }
    val color = when (worst) {
        HealthLevel.OK -> Color(0xFF34C759)
        HealthLevel.WARNING -> Color(0xFFFF9500)
        HealthLevel.CRITICAL -> MaterialTheme.colorScheme.error
        HealthLevel.UNKNOWN, null -> MaterialTheme.colorScheme.outlineVariant
    }
    Box(Modifier.size(10.dp).background(color, CircleShape))
}

@Composable
private fun PowerMenu(
    busy: Boolean,
    onAction: (ServicePowerAction) -> Unit,
    onRefresh: () -> Unit,
    onLogs: () -> Unit,
    onRemove: () -> Unit,
    workers: List<DeploymentNode>,
    runsOn: String?,
    onPlace: (String) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    var placing by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }, enabled = !busy) {
            Icon(Icons.Filled.MoreVert, contentDescription = stringResource(R.string.service_actions))
        }
        DropdownMenu(expanded = placing, onDismissRequest = { placing = false }) {
            workers.forEach { node ->
                DropdownMenuItem(
                    text = {
                        Text(
                            node.name.ifEmpty { node.endpoint.host } +
                                if (node.id == runsOn) "  ✓" else ""
                        )
                    },
                    onClick = { placing = false; if (node.id != runsOn) onPlace(node.id) }
                )
            }
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.service_start)) },
                onClick = { onAction(ServicePowerAction.START); open = false }
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.service_stop)) },
                onClick = { onAction(ServicePowerAction.STOP); open = false }
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.service_restart)) },
                onClick = { onAction(ServicePowerAction.RESTART); open = false }
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.service_refresh)) },
                onClick = { onRefresh(); open = false }
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.service_logs)) },
                onClick = { onLogs(); open = false }
            )
            if (workers.isNotEmpty()) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.service_runs_on)) },
                    onClick = { open = false; placing = true }
                )
            }
            DropdownMenuItem(
                text = {
                    Text(
                        stringResource(R.string.remove_service),
                        color = MaterialTheme.colorScheme.error,
                    )
                },
                onClick = { onRemove(); open = false }
            )
        }
    }
}

@Composable
private fun ConnectionRow(deployment: Deployment, check: ConnectionCheck) {
    val scope = rememberCoroutineScope()
    var state by remember(deployment.id) { mutableStateOf<ConnectionCheck.Result?>(null) }
    var running by remember(deployment.id) { mutableStateOf(false) }

    val onFallback by check.onFallback.collectAsState()

    GroupedSection {
        if (deployment.id in onFallback) {
            GroupedRow {
                Text(
                    stringResource(R.string.server_on_fallback),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.warning,
                )
            }
        }
        ActionRow(
            text = stringResource(if (running) R.string.checking else R.string.check_connection),
            onClick = {
                running = true
                scope.launch {
                    state = check.check(deployment)
                    running = false
                }
            },
            enabled = !running,
            showDivider = state != null,
        )
        when (val result = state) {
            is ConnectionCheck.Result.Reachable -> GroupedRow(showDivider = false) {
                Text(
                    stringResource(R.string.reachable, result.identity, result.system),
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.secondaryLabel,
                )
            }
            is ConnectionCheck.Result.Refused -> GroupedRow(showDivider = false) {
                Text(
                    stringResource(R.string.unreachable, result.reason),
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.danger,
                )
            }
            null -> Unit
        }
    }
}

/** Connection, relay, sites and the cards come before protection */
private const val GENERAL_SECURITY_ITEM = 4

/** Scrolls Protection in first, then lets the tour frame it */
private suspend fun revealSecurity(list: LazyListState) {
    AppTourFocus.arriving.value = AppTourStep.SECURITY
    try {
        delay(300)
        list.animateScrollToItem(GENERAL_SECURITY_ITEM)
    } finally {
        AppTourFocus.arriving.compareAndSet(AppTourStep.SECURITY, null)
    }
}

/** Sideways across the page moves to the next section */
private fun Modifier.sectionSwipe(
    sections: List<ServerSection>,
    current: ServerSection,
    onSelect: (ServerSection) -> Unit,
): Modifier = pointerInput(sections, current) {
    var travelled = 0f
    detectHorizontalDragGestures(
        onDragStart = { travelled = 0f },
        onDragEnd = {
            val step = if (travelled < 0) 1 else -1
            val next = sections.indexOf(current) + step
            if (kotlin.math.abs(travelled) > 64.dp.toPx() && next in sections.indices) {
                onSelect(sections[next])
            }
        },
        onHorizontalDrag = { change, amount ->
            travelled += amount
            change.consume()
        },
    )
}

/** The next section slides in from its side */
internal fun sectionSlide(forward: Boolean): ContentTransform {
    val spec = tween<IntOffset>(durationMillis = 320, easing = FastOutSlowInEasing)
    val enter = slideInHorizontally(spec) { width -> if (forward) width else -width }
    val exit = slideOutHorizontally(spec) { width -> if (forward) -width else width }
    return ContentTransform(enter, exit, sizeTransform = SizeTransform(clip = true))
}

@Composable
private fun InterruptedMove(deployment: Deployment, moves: com.skaymer.gryonixnexus.app.servers.ServiceMoveViewModel) {
    val record by moves.interrupted.collectAsState()
    val pending = record ?: return
    val service = ServiceRegistry.service(ServiceID(pending.service))?.displayName ?: pending.service
    val target = deployment.nodes.firstOrNull { it.id == pending.target }
        ?.let { it.name.ifEmpty { it.endpoint.host } }.orEmpty()
    InterruptedMoveCard(deployment, moves, service, target)
}
