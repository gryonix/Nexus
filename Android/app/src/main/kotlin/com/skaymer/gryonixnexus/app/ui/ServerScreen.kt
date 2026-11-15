package com.skaymer.gryonixnexus.app.ui

import androidx.compose.material.icons.automirrored.outlined.ListAlt
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.AddCircleOutline
import com.skaymer.gryonixnexus.app.ui.design.SymbolIcons
import com.skaymer.gryonixnexus.app.servers.MetricsFormat
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
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.MoreHoriz
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
import androidx.compose.runtime.CompositionLocalProvider
import com.skaymer.gryonixnexus.app.ui.design.PullToRefresh
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.key
import androidx.compose.ui.Modifier
import kotlin.math.roundToInt
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.DisclosureChevron
import androidx.compose.ui.text.font.FontWeight
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
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
    /** The bar's "…" — see `ServerBarMenu` */
    serverBar: ServerBarCommands? = null,
) {
    val context = remember(deployment) { deployment.serviceContext }
    var showingConfiguration by rememberSaveable(deployment.id) { mutableStateOf(false) }
    val groupOverride by tabs.groupServicesOverride.collectAsState()
    val grouped = remember(deployment, groupOverride) { tabs.groupsServices(deployment.services) }
    val shelves = remember(deployment) { shelves(deployment.services) }
    val flat = remember(deployment) { deployment.services.toList() }

    LaunchedEffect(deployment.id, deployment.services) { services.refresh(deployment) }
    LaunchedEffect(deployment.id) { agentSelfUpdate.load(deployment) }
    var refreshTick by remember(deployment.id) { mutableIntStateOf(0) }
    val appContext = androidx.compose.ui.platform.LocalContext.current.applicationContext
    val homeOnlyScope = rememberCoroutineScope()
    val serviceTools = remember(backups, updates, fleet, hostActions) {
        val app = appContext as? com.skaymer.gryonixnexus.app.GryonixApplication
        val homeOnly = com.skaymer.gryonixnexus.app.servers.HomeOnlyController(
            scope = homeOnlyScope,
            persist = { fleet.update(it) },
            reprovision = { app?.reprovisionRelay(it) },
            guardHost = { changed, host, clearing -> hostActions.setLockdown(changed, host, true, clearing) },
            probe = { changed, ports -> app?.probePublicPorts(changed, ports) },
            dns = app?.homeOnlyDNS(),
            rootCA = { changed -> app?.localRootCA(changed).orEmpty() },
            localAliases = { changed, host, on -> checkNotNull(app).localAliases(changed, host, on) },
            keepPortsHome = { changed, ports -> app?.setHomeOnlyPorts(changed, ports); Unit },
        )
        ServiceTools(
            backups, updates, homeOnly,
            reapply = { changed, service -> adding.reapply(changed, service) },
            audioOutputs = { changed -> app?.audioOutputs(changed).orEmpty() },
            odio = { changed, method, path, body -> checkNotNull(app).odio(changed, method, path, body) },
            names = app?.serviceNames,
            rename = { changed, id, name -> homeOnlyScope.launch { app?.renameService(changed, id.rawValue, name) } },
        )
    }
    LaunchedEffect(deployment.id) { moves.refreshInterrupted(deployment.id) }
    LaunchedEffect(deployment.id) {
        (appContext as? com.skaymer.gryonixnexus.app.GryonixApplication)?.loadAppModules(deployment)
    }
    LaunchedEffect(deployment.id) {
        (appContext as? com.skaymer.gryonixnexus.app.GryonixApplication)?.loadServiceNames(deployment)
    }
    LaunchedEffect(deployment.id) { (appContext as? com.skaymer.gryonixnexus.app.GryonixApplication)?.notify?.sync(deployment) }
    LaunchedEffect(deployment.id) { (appContext as? com.skaymer.gryonixnexus.app.GryonixApplication)?.homeDoors?.load(deployment) }
    DisposableEffect(deployment.id) { onDispose { services.stop() } }
    val serviceStates by services.states.collectAsState()
    val fleetDeployments by fleet.deployments.collectAsState()

    DisposableEffect(deployment.id) { onDispose { updates.reset() } }
    var showingUpdates by rememberSaveable(deployment.id) { mutableStateOf(false) }
    var showingSystemUpdate by rememberSaveable(deployment.id) { mutableStateOf(false) }
    var showingSystem by rememberSaveable(deployment.id) { mutableStateOf(false) }
    var showingSwap by rememberSaveable(deployment.id) { mutableStateOf(false) }
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
    var alertCard by remember(deployment.id) { mutableStateOf<com.skaymer.gryonixnexus.app.notify.AlertCard?>(null) }
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
    var page by rememberSaveable(deployment.id) { mutableStateOf<String?>(null) }
    var filesNode by rememberSaveable(deployment.id) { mutableStateOf<String?>(null) }
    val sectionIcons by tabs.sectionIcons.collectAsState()
    val tunnelActive = vpnTunnel.state.collectAsState().value.carriesASession()
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
    val alertAsked by navigator.askedSection.collectAsState()
    LaunchedEffect(alertAsked, ordered) {
        val asked = navigator.takeSection(deployment.id) ?: return@LaunchedEffect
        if (asked in ordered) currentRaw = asked.raw
        navigator.takeService(deployment.id)?.let { logsService = it }
        navigator.takeAlert(deployment.id)?.let { alertCard = it }
    }
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

    val categoryExtras: (String) -> (@Composable () -> Unit)? = { id ->
        when (id) {
            "mail" -> if (MailboxesViewModel.hasEngine(deployment) || DKIMViewModel.hasMailEngine(deployment)) ({
                if (MailboxesViewModel.hasEngine(deployment)) MailboxesCard({ showingMailboxes = true })
                if (DKIMViewModel.hasMailEngine(deployment)) DKIMCard({ showingDKIM = true }, showDivider = false)
            }) else null
            "passwords" -> if (canToggleVaultwardenSignups(deployment) || VaultwardenTwoFactorViewModel.canShow(deployment)) ({
                if (canToggleVaultwardenSignups(deployment)) {
                    VaultwardenSignupsCard(deployment, { open ->
                        val settings = deployment.serviceSettings.copy(vaultwardenAllowSignups = open)
                        ServiceRegistry.service(ServiceID.VAULTWARDEN)?.let {
                            adding.reapply(deployment.copy(serviceSettings = settings), it)
                        }
                    }, VaultwardenTwoFactorViewModel.canShow(deployment))
                }
                if (VaultwardenTwoFactorViewModel.canShow(deployment)) VaultwardenTwoFactorCard(deployment, false)
            }) else null
            "ai" -> if (ModelKeysViewModel.canManage(deployment) || LocalModelsViewModel.canManage(deployment)) ({
                if (ModelKeysViewModel.canManage(deployment)) ModelKeysCard({ showingModelKeys = true })
                if (LocalModelsViewModel.canManage(deployment)) LocalModelsCard({ showingLocalModels = true }, false)
            }) else null
            "games" -> if (ModsViewModel.canManage(deployment)) ({
                ModsCard(
                    callsThemPlugins = AgentModOperations.slot(deployment.serviceSettings.minecraftJavaFlavour) == ModSlot.MOD_SLOT_PLUGINS,
                    onOpen = { showingMods = true },
                    showDivider = false,
                )
            }) else null
            "mesh" -> if (MeshViewModel.managesMesh(deployment, agentTransportAvailable = true)) ({
                MeshCard(mesh, { showingMesh = true }, false)
            }) else if (MeshViewModel.usesTailscaleAccount(deployment)) ({
                val uri = androidx.compose.ui.platform.LocalUriHandler.current
                ValueRow(
                    title = stringResource(R.string.mesh),
                    value = null,
                    onClick = { uri.openUri(MeshViewModel.TAILSCALE_DEVICES_URL) },
                    showDivider = false,
                )
            }) else null
            else -> null
        }
    }
    val openPage = page
    if (openPage != null) {
        val back = { page = null }
        BackHandler { back() }
        val title = pageTitle(openPage)
        DisposableEffect(title) {
            val refresh: (() -> Unit)? = when (openPage) {
                PAGE_CROWDSEC -> ({ security.load(deployment); security.loadAutoRules(deployment) })
                PAGE_SSH -> ({ security.loadSshAccess(deployment); security.loadSshUsers(deployment) })
                else -> null
            }
            pushed.push(title, onBack = back, onRefresh = refresh)
            onDispose { pushed.clear() }
        }
        when (openPage) {
            PAGE_CROWDSEC -> CrowdSecPage(deployment, security, store)
            PAGE_SSH -> SshAccessPage(deployment, security)
            PAGE_LOCKDOWN -> LockdownPage(
                deployment, hostActions,
                (androidx.compose.ui.platform.LocalContext.current.applicationContext as? com.skaymer.gryonixnexus.app.GryonixApplication)?.openAPI,
            )
            PAGE_FILES -> Box(Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground)) {
                FileBrowserSection(deployment, files)
                LaunchedEffect(filesNode) {
                    deployment.nodes.firstOrNull { it.id.toString() == filesNode }?.let { files.open(deployment, it.sshHost) }
                }
            }
            PAGE_HOST -> LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = GroupedContentPadding,
                verticalArrangement = GroupedSpacing,
            ) {
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
            }
            PAGE_AGENT -> LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = GroupedContentPadding,
                verticalArrangement = GroupedSpacing,
            ) {
                item {
                    AgentCard(deployment, agentInstall, onInstalled = { fleet.reload() }, removal = agentRemoval) {
                        if (deployment.usesAgent) {
                            NavRow(Icons.AutoMirrored.Outlined.ListAlt, stringResource(R.string.general_devices), {
                                guard(GatedAction.ACCESS_SCREEN, deployment.name) { showingDevices = true }
                            })
                        }
                    }
                }
                item { AgentSelfUpdateCard(deployment, agentSelfUpdate) }
                if (deployment.usesAgent) item { McpAccessCard(deployment) }
            }
            else -> LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = GroupedContentPadding,
                verticalArrangement = GroupedSpacing,
            ) {
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
            }
        }
    } else Column(Modifier.fillMaxSize()) {
        Box(Modifier.appTourTarget(AppTourTarget.SERVER_STRIP)) {
            ServerSectionsStrip(
                sections = ordered,
                available = available,
                current = current,
                settings = sections,
                deploymentID = deployment.id,
                onSelect = { currentRaw = it.raw },
                onArrange = { arranging = true },
                icons = sectionIcons,
                tunnelActive = tunnelActive,
            )
        }

        PullToRefresh(onRefresh = {
            refreshTick += 1
            services.refresh(deployment)
            agentSelfUpdate.load(deployment)
        }) {
        Box(Modifier.fillMaxSize().sectionSwipe(ordered, current) { currentRaw = it.raw }) {
        key(refreshTick) {
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
                item { Box(Modifier.appTourTarget(AppTourTarget.SERVER_SITES)) { SitesCard(deployment, tabs) } }
                item {
                    ConnectionCard(
                        deployment, relay,
                        onServers = { page = PAGE_MACHINES },
                        onDynamicDNS = if (DynamicDNSViewModel.canManage(deployment)) ({ showingDDNS = true }) else null,
                    )
                }
                item {
                    GeneralLinks(
                        onLogins = { guard(GatedAction.ACCESS_SCREEN, deployment.name) { showingAccess = true } },
                        onConfiguration = { showingConfiguration = true },
                        onSystem = if (systemUpdates != null) ({ showingSystem = true }) else null,
                    )
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
                            SecuritySummary(
                                deployment, security, hostActions,
                                onLockdown = { page = PAGE_LOCKDOWN },
                                onCrowdSec = { page = PAGE_CROWDSEC },
                                onSsh = { page = PAGE_SSH },
                            )
                        }
                    }
                }
                if (com.skaymer.gryonixnexus.app.notify.NotifyViewModel.canManage(deployment)) {
                    item {
                        GroupedSection {
                            NavRow(Icons.Outlined.NotificationsActive, stringResource(R.string.notify_title),
                                { showingNotify = true }, showDivider = false)
                        }
                    }
                }
                item { AgentLink { page = PAGE_AGENT } }
                item {
                    HostActionsCard(
                        deployment, hostActions, wakeOnLAN,
                        onRepair = if (deployment.usesAgent) ({
                            rerunning = true to AddedServiceScripts.scripts(ServiceRegistry.services(deployment.services), deployment)
                        }) else null,
                        onReinstall = {
                            if (deployment.usesAgent) {
                                rerunning = false to AddedServiceScripts.scripts(ServiceRegistry.services(deployment.services), deployment)
                            } else {
                                configurator.adopt(ConfiguratorForm.of(deployment), deployment)
                                navigator.show(AppTab.CONFIGURATOR)
                            }
                        },
                    )
                }
                item { EraseCard { showingErase = true } }
            }

            ServerSection.APPS -> CompositionLocalProvider(LocalServiceTools provides serviceTools) { LazyColumn(
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
                                category, ids, context, serviceStates, deployment, services, store,
                                onLogs = { logsService = it.rawValue },
                                onRemove = { removingService = it.rawValue },
                                onPlace = { service, node -> moves.request(deployment, service, node) },
                                extras = categoryExtras(category.id),
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
                            GroupedRow(
                                onClick = { addingService = true },
                                showDivider = false,
                                leading = { Icon(Icons.Outlined.AddCircleOutline, null, modifier = Modifier.size(22.dp)) },
                                trailing = {
                                    InfoNoteButton(
                                        title = stringResource(R.string.add_service),
                                        note = stringResource(R.string.add_service_hint),
                                    )
                                },
                            ) {
                                Text(stringResource(R.string.add_service), style = MaterialTheme.typography.bodyLarge,
                                    color = Gryonix.colors.accent)
                            }
                        }
                    }
                }
                if (BackupsViewModel.backupCapableServices(deployment).isNotEmpty()) {
                    item { GroupedSection { BackupsCard(deployment, backups, { showingBackups = true }, false) } }
                }
                item { GroupedSection { UpdatesCard(deployment, updates, { showingUpdates = true }, false) } }
            } }

            ServerSection.METRICS -> Column(Modifier.appTourTarget(AppTourTarget.SERVER_METRICS)) {
                Box(Modifier.padding(top = 16.dp)) {
                    ServerMachinesRow(deployment) { page = PAGE_HOST }
                }
                Box(Modifier.weight(1f)) {
                    MetricsSection(fleet, history, board, panels, onlyServer = deployment)
                }
            }
            ServerSection.CONTAINERS -> DockerTabs(deployment) { ContainersSection(fleet, containers, only = deployment.id) }
            ServerSection.VPN ->
                VPNSection(fleet, vpnClients, only = deployment.id, tunnel = vpnTunnel,
                           onChangeRealitySite = adding::changeRealitySite,
                           onRenewRealityKey = adding::renewRealityKey)
            ServerSection.TERMINAL -> ServerTerminalTab(deployment, terminals, shellUsers) { node ->
                filesNode = node.id.toString()
                page = PAGE_FILES
            }
        }
        }
        }
        }
        }
    }

    if (showingUpdates) {
        val parts = remember(deployment.id) { backups.parts() }
        UpdatesDialog(
            deployment, updates,
            onSystemUpdate = systemUpdates?.let { { showingUpdates = false; showingSystemUpdate = true } },
            parts = parts,
            agentSelfUpdate = agentSelfUpdate,
        ) { showingUpdates = false }
    }
    if (showingSystem && systemUpdates != null) {
        SystemDialog(
            deployment,
            updates = systemUpdates,
            onUpdates = { showingSystem = false; showingSystemUpdate = true },
            onSwap = { showingSystem = false; showingSwap = true },
        ) { showingSystem = false }
    }
    if (showingSystemUpdate && systemUpdates != null) {
        SystemUpdateDialog(deployment, systemUpdates) { showingSystemUpdate = false }
    }
    if (showingSwap && systemUpdates != null) {
        SystemSwapDialog(deployment, systemUpdates) { showingSwap = false }
    }
    if (showingBackups) {
        BackupsDialog(deployment, backups, fleetDeployments) { showingBackups = false }
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
            checkMachine = { ids ->
                (appContext as? com.skaymer.gryonixnexus.app.GryonixApplication)?.checkInstall(deployment, ids).orEmpty()
            },
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
        val app = appContext as? com.skaymer.gryonixnexus.app.GryonixApplication
        AddServiceInstallSheet(
            deployment = deployment,
            services = services,
            scripts = scripts,
            makeModel = { app?.let { ConfiguratorViewModel(fleet = it.fleet, secrets = it.secrets) } },
            onInstall = { updated ->
                choosingInstall = null
                app?.fleet?.update(updated)
                adding.install(updated, services, mount)
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
    alertCard?.let { card -> AlertCardDialog(card) { alertCard = null } }
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

    val asked = serverBar?.pending
    var barDialog by remember(deployment.id) { mutableStateOf<ServerBarCommands.Command?>(null) }
    LaunchedEffect(asked) {
        if (asked == null) return@LaunchedEffect
        serverBar.taken()
        if (asked == ServerBarCommands.Command.SECTIONS) arranging = true else barDialog = asked
    }
    val secrets = (androidx.compose.ui.platform.LocalContext.current.applicationContext
        as com.skaymer.gryonixnexus.app.GryonixApplication).secrets
    when (barDialog) {
        ServerBarCommands.Command.CONNECTION ->
            ServerSettingsDialog(deployment, fleet, secrets, store) { barDialog = null }
        ServerBarCommands.Command.KEY -> ServerAccessDialog(
            deployment = deployment,
            secrets = secrets,
            onCredentialsChanged = { fleet.reload() },
            onClose = { barDialog = null },
        )
        else -> Unit
    }
}

private const val PAGE_AGENT = "agent"
private const val PAGE_CROWDSEC = "crowdsec"
private const val PAGE_SSH = "ssh"
private const val PAGE_LOCKDOWN = "lockdown"
private const val PAGE_HOST = "host"
private const val PAGE_MACHINES = "machines"
private const val PAGE_FILES = "files"

/** "Server 31 %" above the panels; opens the machine's own page */
@Composable
private fun ServerMachinesRow(deployment: Deployment, onOpen: () -> Unit) {
    val app = androidx.compose.ui.platform.LocalContext.current.applicationContext
        as? com.skaymer.gryonixnexus.app.GryonixApplication
    val readings = app?.metrics?.card(deployment.id)?.collectAsState()?.value.orEmpty()
    GroupedSection {
        deployment.nodes.forEachIndexed { index, node ->
            val cpu = readings[node.sshHost]?.snapshot?.cpuPercent
            GroupedRow(
                onClick = onOpen,
                showDivider = index != deployment.nodes.lastIndex,
                trailing = {
                    Text(
                        cpu?.let { "${it.roundToInt()}%" } ?: "—",
                        style = MaterialTheme.typography.bodySmall,
                        color = Gryonix.colors.secondaryLabel,
                    )
                    DisclosureChevron()
                },
            ) {
                Text(
                    if (deployment.isMultiHost) node.name.ifEmpty { node.endpoint.host }
                    else stringResource(R.string.host_badge_server),
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = Gryonix.colors.label,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

@Composable
private fun pageTitle(page: String): String = when (page) {
    PAGE_CROWDSEC -> "CrowdSec"
    PAGE_SSH -> stringResource(R.string.security_ssh_title)
    PAGE_LOCKDOWN -> stringResource(R.string.actions_lockdown)
    PAGE_HOST -> stringResource(R.string.host_badge_server)
    PAGE_MACHINES -> stringResource(R.string.agent_servers)
    PAGE_FILES -> stringResource(R.string.terminal_files)
    else -> stringResource(R.string.general_agent)
}

private fun shelves(services: Set<ServiceID>): List<Pair<ServiceCategory, List<ServiceID>>> {
    val byShelf = LinkedHashMap<ServiceCategory, MutableList<ServiceID>>()
    for (id in services) {
        val shelf = ServiceRegistry.service(id)?.displayCategory ?: continue
        byShelf.getOrPut(shelf) { mutableListOf() }.add(id)
    }
    return byShelf.entries.sortedBy { it.key }.map { it.key to it.value }
}

/** One category as its own card, folded away by default */
@Composable
private fun Shelf(
    category: ServiceCategory,
    ids: List<ServiceID>,
    context: com.skaymer.gryonixnexus.catalog.ServiceContext,
    states: Map<ServiceID, ServiceState>,
    deployment: Deployment,
    services: ServiceControlViewModel,
    store: SettingsStore,
    onLogs: (ServiceID) -> Unit,
    onRemove: (ServiceID) -> Unit,
    onPlace: (ServiceID, String) -> Unit,
    extras: (@Composable () -> Unit)?,
) {
    val key = "serviceCategoryExpanded.${deployment.id}.${category.id}"
    var expanded by remember(key) { mutableStateOf(store.boolean(key) ?: false) }
    GroupedSection(dividerInset = 46.dp) {
        GroupedRow(
            onClick = {
                expanded = !expanded
                store.setBoolean(key, expanded)
            },
            showDivider = expanded,
            leading = { Icon(SymbolIcons.of(category.systemImage), null, modifier = Modifier.size(22.dp)) },
            trailing = {
                Icon(
                    if (expanded) Icons.Filled.ExpandMore else Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    modifier = Modifier.size(22.dp),
                )
            },
        ) {
            Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                Text(categoryTitle(category), style = MaterialTheme.typography.bodyLarge, color = Gryonix.colors.label,
                    modifier = Modifier.weight(1f, fill = false))
                Text("${ids.size}", style = MaterialTheme.typography.bodyLarge, color = Gryonix.colors.secondaryLabel,
                    modifier = Modifier.padding(start = 8.dp))
            }
        }
        if (expanded) {
            ids.forEach {
                ServiceRow(
                    it, context, states[it], deployment, services, onLogs, onRemove, onPlace,
                    showDivider = it != ids.last() || extras != null,
                )
            }
            extras?.invoke()
        }
    }
}

@Composable
internal fun categoryTitle(category: ServiceCategory): String = when (category.id) {
    "mail" -> stringResource(R.string.category_mail)
    "passwords" -> stringResource(R.string.category_passwords)
    "secrets" -> stringResource(R.string.category_secrets)
    "files" -> stringResource(R.string.category_files)
    "photos" -> stringResource(R.string.category_photos)
    "media" -> stringResource(R.string.category_media)
    "code" -> stringResource(R.string.category_code)
    "network" -> stringResource(R.string.category_network)
    "vpn" -> stringResource(R.string.category_vpn)
    "mesh" -> stringResource(R.string.category_mesh)
    "dashboard" -> stringResource(R.string.category_dashboard)
    "sso" -> stringResource(R.string.category_sso)
    "games" -> stringResource(R.string.category_games)
    "ai" -> stringResource(R.string.category_ai)
    "automation" -> stringResource(R.string.category_automation)
    "smart-home" -> stringResource(R.string.category_smart_home)
    "remote-access" -> stringResource(R.string.category_remote_access)
    "audio" -> stringResource(R.string.category_audio)
    else -> category.title
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
    val title = serviceTitle(service, id, deployment)
    val workers = deployment.nodes.filter { it.runsServices }
    val runsOn = deployment.nodeRunning(id)
    val openAPI = (androidx.compose.ui.platform.LocalContext.current.applicationContext as? com.skaymer.gryonixnexus.app.GryonixApplication)?.openAPI
    val offersAccess = openAPI != null && deployment.usesAgent && com.skaymer.gryonixnexus.catalog.ServiceAPIGroups.groups(id).isNotEmpty()
    var showingAccess by remember(deployment.id, id) { mutableStateOf(false) }
    if (showingAccess && openAPI != null) {
        ServiceOpenAPISheet(deployment, id, title, openAPI, onClose = { showingAccess = false })
    }
    var expanded by rememberSaveable(deployment.id, id) { mutableStateOf(false) }
    GroupedRow(
        showDivider = showDivider || expanded,
        onClick = { expanded = !expanded },
        leading = { HealthDot(state) },
        trailing = {
            if (service != null && workers.size > 1) PowerMenu(
                busy = state?.isBusy == true,
                onAction = { services.power(deployment, id, it) },
                onRefresh = { services.refresh(deployment) },
                onLogs = { onLogs(id) },
                onRemove = { onRemove(id) },
                onAccess = if (offersAccess) ({ showingAccess = true }) else null,
                workers = if (workers.size > 1) workers else emptyList(),
                runsOn = runsOn?.id,
                onPlace = { node -> onPlace(id, node) },
            )
            Icon(
                if (expanded) Icons.Filled.ExpandMore else Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                modifier = Modifier.size(22.dp),
            )
        },
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                title,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
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
            if (id in deployment.homeOnlyServices) HomeBadge()
        }
    }
    if (expanded && service != null) {
        ServiceDetail(
            service, deployment, services,
            onLogs = { onLogs(id) },
            onRemove = { onRemove(id) },
            onAccess = if (offersAccess) ({ showingAccess = true }) else null,
        )
    }
}

/** A service's given name here, or the catalog one */
@Composable
private fun serviceTitle(service: com.skaymer.gryonixnexus.catalog.ManagedService?, id: ServiceID, deployment: Deployment): String {
    val names = LocalServiceTools.current?.names ?: return service?.displayName ?: id.rawValue
    val servers by names.servers.collectAsState()
    return servers[deployment.id]?.get(id.rawValue) ?: service?.displayName ?: id.rawValue
}

@Composable
private fun HomeBadge() {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Icon(Icons.Outlined.Home, contentDescription = null, modifier = Modifier.size(14.dp), tint = Gryonix.colors.secondaryLabel)
        Text(stringResource(R.string.home_only_badge), style = MaterialTheme.typography.bodySmall, color = Gryonix.colors.secondaryLabel)
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
                RefusalAdvice(it)
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
    onAccess: (() -> Unit)?,
    workers: List<DeploymentNode>,
    runsOn: String?,
    onPlace: (String) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    var placing by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }, enabled = !busy) {
            Icon(Icons.Filled.MoreHoriz, contentDescription = stringResource(R.string.service_actions))
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
            if (onAccess != null) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.api_access_row)) },
                    onClick = { open = false; onAccess() }
                )
            }
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
