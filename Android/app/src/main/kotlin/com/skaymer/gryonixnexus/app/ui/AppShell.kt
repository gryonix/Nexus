package com.skaymer.gryonixnexus.app.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.layout.Box
import com.skaymer.gryonixnexus.app.shell.AppTourState
import com.skaymer.gryonixnexus.app.shell.AppTourRequests
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.geometry.Rect
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.size
import com.skaymer.gryonixnexus.app.updates.AppUpdateViewModel
import com.skaymer.gryonixnexus.app.ui.design.DisclosureChevron
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.IOSBarButton
import com.skaymer.gryonixnexus.app.ui.design.IOSNavBar
import com.skaymer.gryonixnexus.app.ui.design.IOSTabBar
import com.skaymer.gryonixnexus.app.ui.design.IOSTabItem
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.terminal.TerminalDirectHostStore
import com.skaymer.gryonixnexus.app.terminal.ShellUserViewModel
import com.skaymer.gryonixnexus.app.terminal.TerminalSessions
import com.skaymer.gryonixnexus.app.agent.RunningJobs
import com.skaymer.gryonixnexus.app.agent.AgentInstallViewModel
import com.skaymer.gryonixnexus.app.agent.AgentSelfUpdateViewModel
import com.skaymer.gryonixnexus.app.configurator.ConfiguratorViewModel
import com.skaymer.gryonixnexus.app.configurator.ScenarioOption
import com.skaymer.gryonixnexus.app.install.InstallRegistry
import com.skaymer.gryonixnexus.app.secrets.DNSCredentials
import com.skaymer.gryonixnexus.app.secrets.CloudflareTokenStore
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.app.metrics.HistoryViewModel
import com.skaymer.gryonixnexus.app.access.AccessViewModel
import com.skaymer.gryonixnexus.app.devices.DevicesViewModel
import com.skaymer.gryonixnexus.app.mesh.MeshViewModel
import com.skaymer.gryonixnexus.app.metrics.MetricPanelStore
import com.skaymer.gryonixnexus.app.metrics.MetricsBoardViewModel
import com.skaymer.gryonixnexus.app.servers.FleetMetrics
import com.skaymer.gryonixnexus.app.servers.BackupsViewModel
import com.skaymer.gryonixnexus.app.servers.ServiceControlViewModel
import com.skaymer.gryonixnexus.app.servers.UpdatesViewModel
import com.skaymer.gryonixnexus.app.servers.EraseViewModel
import com.skaymer.gryonixnexus.app.servers.DeploymentTransferService
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.app.servers.AdoptViewModel
import com.skaymer.gryonixnexus.app.servers.FleetRepository
import com.skaymer.gryonixnexus.app.servers.RelayStatusViewModel
import com.skaymer.gryonixnexus.app.servers.HostActionsViewModel
import com.skaymer.gryonixnexus.app.containers.ContainersViewModel
import com.skaymer.gryonixnexus.app.files.FileBrowserViewModel
import com.skaymer.gryonixnexus.app.logs.ServiceLogsViewModel
import com.skaymer.gryonixnexus.app.dns.DKIMViewModel
import com.skaymer.gryonixnexus.app.dns.DynamicDNSViewModel
import com.skaymer.gryonixnexus.app.hosts.HostProbesViewModel
import com.skaymer.gryonixnexus.app.security.SecurityViewModel
import com.skaymer.gryonixnexus.app.ai.LocalModelsViewModel
import com.skaymer.gryonixnexus.app.servers.ModsViewModel
import com.skaymer.gryonixnexus.app.ai.ModelKeysViewModel
import com.skaymer.gryonixnexus.app.mail.MailboxesViewModel
import com.skaymer.gryonixnexus.app.servers.AddMachineViewModel
import com.skaymer.gryonixnexus.app.servers.AddServiceViewModel
import com.skaymer.gryonixnexus.app.servers.ServiceRemovalViewModel
import com.skaymer.gryonixnexus.app.vpn.VPNClientsViewModel
import com.skaymer.gryonixnexus.app.vpn.VpnTunnel
import com.skaymer.gryonixnexus.app.session.ConnectionCheck
import com.skaymer.gryonixnexus.app.shell.AppNavigator
import com.skaymer.gryonixnexus.app.shell.AppTab
import com.skaymer.gryonixnexus.app.shell.DisplaySettings
import com.skaymer.gryonixnexus.app.shell.ServerSectionSettings
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.app.shell.WelcomeState
import com.skaymer.gryonixnexus.app.shell.ShellSections
import com.skaymer.gryonixnexus.app.shell.TabBarSettings
import com.skaymer.gryonixnexus.core.Artifact
import com.skaymer.gryonixnexus.app.licensing.LicenseGate
import com.skaymer.gryonixnexus.app.licensing.LicensePrompt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppShell(
    tabs: TabBarSettings,
    /** How each server's own sections are arranged — see `ServerSectionSettings` */
    sections: ServerSectionSettings,
    store: SettingsStore,
    /** Whether the welcome has been said — see `WelcomeState` */
    welcome: WelcomeState,
    fleet: FleetRepository,
    navigator: AppNavigator,
    configurator: ConfiguratorViewModel,
    secrets: SecretStore,
    check: ConnectionCheck,
    metrics: FleetMetrics,
    history: HistoryViewModel,
    board: MetricsBoardViewModel,
    panels: MetricPanelStore,
    services: ServiceControlViewModel,
    updates: UpdatesViewModel,
    appUpdates: AppUpdateViewModel,
    backups: BackupsViewModel,
    mesh: MeshViewModel,
    access: AccessViewModel,
    devices: DevicesViewModel,
    installs: InstallRegistry,
    vpnClients: VPNClientsViewModel,
    /** The tunnel this device brings up itself — see `VpnTunnel` */
    vpnTunnel: VpnTunnel,
    containers: ContainersViewModel,
    erase: EraseViewModel,
    /** Restart sshd, reboot, and the guard over the admin panels */
    hostActions: HostActionsViewModel,
    wakeOnLAN: com.skaymer.gryonixnexus.app.servers.WakeOnLANViewModel,
    /** The server's own disk — see `FileBrowserViewModel` */
    files: FileBrowserViewModel,
    /** One service's container log — see `ServiceLogsViewModel` */
    serviceLogs: ServiceLogsViewModel,
    /** Taking ONE service off a server — see `ServiceRemovalViewModel` */
    serviceRemoval: ServiceRemovalViewModel,
    serviceMove: com.skaymer.gryonixnexus.app.servers.ServiceMoveViewModel,
    /** Adding one to a server that already runs — see `AddServiceViewModel` */
    addService: AddServiceViewModel,
    /** The mail engine's own accounts — see `MailboxesViewModel` */
    mailboxes: MailboxesViewModel,
    modelKeys: ModelKeysViewModel,
    localModels: LocalModelsViewModel,
    /** Jars sent up for a Minecraft (Java) server — see `ModsViewModel` */
    mods: ModsViewModel,
    /** A host keeping its own A records current — see `DynamicDNSViewModel` */
    dynamicDNS: DynamicDNSViewModel,
    /** The host's CrowdSec defence and what it caught — see `SecurityViewModel` */
    security: SecurityViewModel,
    /** Each machine's own tunnel, memory and volumes — see `HostCard` */
    hostProbes: HostProbesViewModel,
    /** A machine added to a server that already exists */
    addMachine: AddMachineViewModel,
    /** The DKIM records a mail server minted — see `DKIMViewModel` */
    dkim: DKIMViewModel,
    /** Where a shell gets its own connection — see `TerminalSessions` */
    terminals: TerminalSessions,
    /** Putting the control-plane agent on a server — see `AgentInstallViewModel` */
    agentInstall: AgentInstallViewModel,
    agentSelfUpdate: AgentSelfUpdateViewModel,
    /** The Cloudflare API tokens — see `CloudflareTokenStore` */
    cloudflare: CloudflareTokenStore,
    /** The relay path's rows on a scenario B server */
    relayStatus: RelayStatusViewModel,
    dnsCredentials: DNSCredentials,
    /** Machines the app never set up, reachable from the terminal */
    terminalHosts: TerminalDirectHostStore,
    /** Taking over a machine that already runs the agent */
    adopt: AdoptViewModel,
    /** Moving a server between devices — see `DeploymentTransferService` */
    transfer: DeploymentTransferService,
    runningJobs: RunningJobs,
    /** Take a server off the list */
    onForget: (String) -> Unit,
    /** Making an account to open a shell with — see `CreateShellUserSheet` */
    shellUsers: ShellUserViewModel? = null,
    agentRemoval: com.skaymer.gryonixnexus.app.agent.AgentRemoval? = null,
    systemUpdates: com.skaymer.gryonixnexus.app.servers.SystemUpdateViewModel? = null,
) {
    val revision by store.revision.collectAsState()
    val order by tabs.order.collectAsState()
    val hidden by tabs.hidden.collectAsState()

    val visible = remember(revision, order, hidden) {
        ShellSections.visible(
            tabs.visibleTabs,
            metricsRaw = store.string(DisplaySettings.METRICS_PLACEMENT_KEY),
            vpnRaw = store.string(DisplaySettings.VPN_PLACEMENT_KEY),
            containersRaw = store.string(DisplaySettings.CONTAINERS_PLACEMENT_KEY),
            terminalRaw = store.string(DisplaySettings.TERMINAL_PLACEMENT_KEY)
        )
    }

    val isTablet = LocalConfiguration.current.smallestScreenWidthDp >= 600
    val capacity = ShellSections.barCapacity(isTablet)
    val onBar = ShellSections.onBar(visible, capacity)
    val behindMore = ShellSections.behindMore(visible, capacity)

    val tunnelState by vpnTunnel.state.collectAsState()
    val tunnelCarriesASession = tunnelState.carriesASession()

    var selected by rememberSaveable { mutableStateOf(tabs.effectiveStartTab.key) }
    var showingMoreList by rememberSaveable { mutableStateOf(false) }

    val current = AppTab.of(selected)?.takeIf { it in visible } ?: visible.first()
    val inOverflow = current in behindMore

    val openServerID by navigator.openServerID.collectAsState()
    val deployments by fleet.deployments.collectAsState()
    val openServer = remember(openServerID, deployments) {
        openServerID?.let { id -> deployments.firstOrNull { it.id == id } }
    }
    val showingServer = openServer != null && current == AppTab.SERVERS && !showingMoreList

    LaunchedEffect(deployments) { metrics.sync(deployments) }
    val license by LicenseGate.status.collectAsState()
    LaunchedEffect(license) { fleet.reload() }
    LicensePromptHost(store, fleet)

    val requestedSection by navigator.openSection.collectAsState()
    LaunchedEffect(requestedSection) {
        val tab = requestedSection ?: return@LaunchedEffect
        selected = tab.key
        navigator.closeServer()
        navigator.sectionShown()
    }

    var openArtifact by remember { mutableStateOf<Artifact?>(null) }
    var addingHost by rememberSaveable { mutableStateOf(false) }
    val fleetBar = remember { FleetBarCommands() }
    val metricsBar = remember { MetricsBarCommands() }
    val pushed = remember { PushedScreen() }
    val serverPushed = remember { PushedScreen() }
    var installing by rememberSaveable { mutableStateOf(false) }
    var wizardScenario by rememberSaveable { mutableStateOf<String?>(null) }
    var showingHistory by rememberSaveable { mutableStateOf(false) }
    var showingWelcome by rememberSaveable { mutableStateOf(!welcome.hasBeenShown) }
    val tourState = remember(store) { AppTourState(store) }
    var tourStep by rememberSaveable { mutableStateOf<AppTourStep?>(null) }
    var tourOpenedServer by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(tourStep) {
        AppTourFocus.step.value = tourStep
        if (tourStep?.section != null) {
            selected = AppTab.SERVERS.key
            if (navigator.openServerID.value == null) {
                deployments.firstOrNull()?.let {
                    navigator.open(it.id)
                    tourOpenedServer = true
                }
            }
        } else if (tourOpenedServer) {
            navigator.closeServer()
            tourOpenedServer = false
        }
    }
    val tourRequests by AppTourRequests.count.collectAsState()
    LaunchedEffect(tourRequests) {
        if (tourRequests > 0) {
            selected = AppTab.SERVERS.key
            tourStep = AppTourStep.entries.first()
        }
    }
    val savedDeployment by configurator.savedDeployment.collectAsState()
    val generated by configurator.bundle.collectAsState()
    val showingArtifact = openArtifact != null && current == AppTab.CONFIGURATOR
    val showingAddHost = addingHost && current == AppTab.SERVERS && !showingMoreList
    val showingInstall = installing && current == AppTab.CONFIGURATOR &&
        savedDeployment != null && generated != null && !showingMoreList
    val showingWizard = current == AppTab.CONFIGURATOR && wizardScenario != null &&
        !showingMoreList && !showingArtifact && !showingInstall
    BackHandler(enabled = showingServer) { navigator.closeServer() }
    BackHandler(enabled = showingArtifact) { openArtifact = null }
    BackHandler(enabled = showingAddHost) { addingHost = false }
    BackHandler(enabled = showingInstall) { installing = false }
    BackHandler(enabled = showingWizard) {
        wizardScenario = null
        configurator.discardBundle()
    }

    if (showingHistory) {
        ConfiguratorHistoryDialog(
            entries = configurator.historyEntries(),
            onRestore = { configurator.restore(it) },
            onDelete = { configurator.deleteFromHistory(it) },
            onClose = { showingHistory = false },
        )
    }

    EraseRunDialog(
        erase = erase,
        name = { id -> deployments.firstOrNull { it.id == id }?.name.orEmpty() },
        onErased = { id ->
            navigator.closeServer()
            onForget(id)
        },
    )

    if (showingWelcome) {
        WelcomeSheet(
            onConfigure = {
                showingWelcome = false
                welcome.markShown()
                selected = AppTab.CONFIGURATOR.key
            },
            onDismiss = {
                showingWelcome = false
                welcome.markShown()
                if (!tourState.hasBeenShown) tourStep = AppTourStep.entries.first()
            },
        )
    }

    Box(Modifier.fillMaxSize()) {
        Scaffold(
            modifier = Modifier.fillMaxSize(),
            topBar = {
                val back: (() -> Unit)? = when {
                    showingInstall -> ({ installing = false })
                    showingAddHost -> ({ addingHost = false })
                    showingArtifact -> ({ openArtifact = null })
                    showingServer ->
                        if (serverPushed.isShowing) serverPushed.onBack
                        else ({ navigator.closeServer() })
                    showingWizard -> ({
                        wizardScenario = null
                        configurator.discardBundle()
                    })
                    pushed.isShowing -> pushed.onBack
                    else -> null
                }
                IOSNavBar(
                    title = when {
                        showingAddHost -> stringResource(R.string.add_machine)
                        showingInstall -> stringResource(R.string.install_title)
                        showingArtifact -> openArtifact!!.fileName
                        showingServer ->
                            if (serverPushed.isShowing) serverPushed.title.orEmpty()
                            else openServer!!.name
                        showingWizard && generated != null -> stringResource(R.string.installation_title)
                        showingWizard -> stringResource(R.string.wizard_title)
                        showingMoreList -> stringResource(R.string.tab_more)
                        pushed.isShowing -> pushed.title.orEmpty()
                        else -> stringResource(current.titleRes)
                    },
                    large = back == null,
                    onBack = back,
                    actions = {
                        if (current == AppTab.SERVERS && !showingServer && !showingAddHost &&
                            !showingMoreList && !pushed.isShowing
                        ) {
                            FleetBarMenu(fleetBar)
                        }
                        if (current == AppTab.METRICS && !showingServer && !showingMoreList &&
                            !pushed.isShowing
                        ) {
                            MetricsBarActions(metricsBar)
                        }
                        if (showingWizard) {
                            IOSBarButton(onClick = { showingHistory = true }) {
                                Icon(
                                    Icons.Filled.History,
                                    contentDescription = stringResource(R.string.configurator_history_open),
                                    modifier = Modifier.size(24.dp),
                                )
                            }
                        }
                        if (inOverflow && !showingMoreList) {
                            IOSBarButton(onClick = { showingMoreList = true }) {
                                Icon(
                                    Icons.AutoMirrored.Filled.List,
                                    contentDescription = stringResource(R.string.all_sections),
                                    modifier = Modifier.size(24.dp),
                                )
                            }
                        }
                    },
                )
            },
            bottomBar = {
                Column(Modifier.appTourTarget(AppTourTarget.SECTION_BAR)) {
                    RunningJobsStrip(runningJobs)
                    IOSTabBar {
                        onBar.forEach { tab ->
                            IOSTabItem(
                                icon = tab.icon(tunnelActive = tunnelCarriesASession),
                                label = stringResource(tab.titleRes),
                                selected = !showingMoreList && tab == current,
                                onClick = {
                                    selected = tab.key
                                    showingMoreList = false
                                },
                            )
                        }
                        if (behindMore.isNotEmpty()) {
                            IOSTabItem(
                                icon = Icons.Filled.MoreHoriz,
                                label = stringResource(R.string.tab_more),
                                selected = showingMoreList || inOverflow,
                                onClick = { showingMoreList = true },
                            )
                        }
                    }
                }
            },
            containerColor = Gryonix.colors.groupedBackground,
        ) { padding ->
            Column(Modifier.padding(padding).fillMaxSize()) {
                when {
                    showingMoreList -> OverflowList(behindMore) { tab ->
                        selected = tab.key
                        showingMoreList = false
                    }
                    showingAddHost -> AddHostScreen(fleet, secrets, adopt) { id ->
                        addingHost = false
                        navigator.open(id)
                    }
                    showingServer -> ServerScreen(
                        openServer!!, tabs, check, services, updates, backups, mesh, access,
                        devices, erase, sections, store, fleet, history, containers, vpnClients, vpnTunnel,
                        hostActions, wakeOnLAN, files, serviceLogs, serviceRemoval, addService, mailboxes,
                        modelKeys,
                        localModels,
                        mods,
                        dynamicDNS, security, hostProbes, addMachine, dkim, configurator,
                        navigator, terminals, serverPushed,
                        agentInstall, agentSelfUpdate, board, panels, cloudflare, relayStatus,
                        moves = serviceMove,
                        shellUsers = shellUsers,
                        agentRemoval = agentRemoval,
                        systemUpdates = systemUpdates,
                    )
                    showingArtifact -> ArtifactScreen(openArtifact!!)
                    showingInstall -> InstallScreen(
                        installs.model(
                            deployment = savedDeployment!!,
                            bundle = generated!!,
                            appPublicKey = configurator.appPublicKey(),
                            homeAddress = configurator.form.value.homeNetworkAddress.trim(),
                        )
                    ) {
                        installing = false
                        selected = AppTab.SERVERS.key
                        if (LicenseGate.unlocked) navigator.open(savedDeployment!!.id)
                    }
                    else -> AnimatedContent(
                        targetState = current,
                        transitionSpec = { sectionSlide(visible.indexOf(targetState) >= visible.indexOf(initialState)) },
                        label = "tab",
                    ) { current -> SectionContent(
                        current, tabs, store, fleet, navigator, configurator, metrics, history,
                        board, panels, vpnClients, vpnTunnel, containers, transfer, secrets, terminals,
                        cloudflare, dnsCredentials, appUpdates, terminalHosts,
                        shellUsers = shellUsers,
                        wakeOnLAN = wakeOnLAN,
                        fleetBar = fleetBar,
                        metricsBar = metricsBar,
                        pushed = pushed,
                        onChangeRealitySite = addService::changeRealitySite,
                        onRenewRealityKey = addService::renewRealityKey,
                        onAddServer = { if (LicensePrompt.allow()) addingHost = true },
                        onInstall = { installing = true },
                        onOpenArtifact = { openArtifact = it },
                        onForget = onForget,
                        wizardScenario = wizardScenario,
                        onPickScenario = { option ->
                            configurator.update {
                                it.copy(topology = option.topology, scope = option.scope)
                            }
                            wizardScenario = option.id
                        },
                    ) }
                }
            }
        }
        tourStep?.let { step ->
            AppTourOverlay(
                step = step,
                onStep = { next ->
                    tourStep = next
                    if (next == null) tourState.markShown()
                },
                onConfigure = {
                    tourStep = null
                    tourState.markShown()
                    selected = AppTab.CONFIGURATOR.key
                },
            )
        }
    }
}

@Composable
private fun OverflowList(sections: List<AppTab>, onPick: (AppTab) -> Unit) {
    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 16.dp),
    ) {
        items(sections) { tab ->
            val last = tab == sections.last()
            Column(Modifier.padding(horizontal = 16.dp)) {
                Column(
                    Modifier
                        .clip(
                            androidx.compose.foundation.shape.RoundedCornerShape(
                                topStart = if (tab == sections.first()) 10.dp else 0.dp,
                                topEnd = if (tab == sections.first()) 10.dp else 0.dp,
                                bottomStart = if (last) 10.dp else 0.dp,
                                bottomEnd = if (last) 10.dp else 0.dp,
                            )
                        )
                        .background(Gryonix.colors.cardBackground)
                ) {
                    GroupedRow(
                        onClick = { onPick(tab) },
                        showDivider = !last,
                        leading = { Icon(tab.icon, contentDescription = null) },
                        trailing = { DisclosureChevron() },
                    ) {
                        RowLabel(stringResource(tab.titleRes))
                    }
                }
            }
        }
    }
}

@Composable
private fun SectionContent(
    tab: AppTab,
    tabs: TabBarSettings,
    store: SettingsStore,
    fleet: FleetRepository,
    navigator: AppNavigator,
    configurator: ConfiguratorViewModel,
    metrics: FleetMetrics,
    history: HistoryViewModel,
    board: MetricsBoardViewModel,
    panels: MetricPanelStore,
    vpnClients: VPNClientsViewModel,
    /** The tunnel this device brings up itself — see `VpnTunnel` */
    vpnTunnel: VpnTunnel,
    containers: ContainersViewModel,
    transfer: DeploymentTransferService,
    secrets: SecretStore,
    /** Where a shell gets its own connection — see `TerminalSessions` */
    terminals: TerminalSessions,
    cloudflare: CloudflareTokenStore,
    /** Every DNS token, as one list — see `DNSCredentials` */
    dnsCredentials: DNSCredentials,
    appUpdates: AppUpdateViewModel,
    terminalHosts: TerminalDirectHostStore,
    /** The Servers bar menu, drawn by the shell — see `FleetBarMenu` */
    fleetBar: FleetBarCommands,
    /** The metrics board's bar, on the same terms — see `MetricsBarActions` */
    metricsBar: MetricsBarCommands,
    pushed: PushedScreen,
    onChangeRealitySite: (Deployment, String) -> Unit,
    onRenewRealityKey: (Deployment, suspend () -> Unit) -> Unit,
    onAddServer: () -> Unit,
    onInstall: () -> Unit,
    onOpenArtifact: (Artifact) -> Unit,
    onForget: (String) -> Unit,
    /** Which scenario the configurator is answering — the shell owns it */
    wizardScenario: String?,
    onPickScenario: (ScenarioOption) -> Unit,
    /** Making an account to open a shell with — see `CreateShellUserSheet` */
    shellUsers: ShellUserViewModel? = null,
    wakeOnLAN: com.skaymer.gryonixnexus.app.servers.WakeOnLANViewModel,
) {
    val shown by fleet.deployments.collectAsState()
    val demoOn = remember(shown) { fleet.isDemo }
    when (tab) {
        AppTab.SERVERS -> ServersSection(
            fleet = fleet,
            store = store,
            metrics = metrics,
            onOpen = { if (LicensePrompt.allow(it)) navigator.open(it) },
            onForget = onForget,
            transfer = transfer,
            secrets = secrets,
            bar = fleetBar,
            onAddServer = onAddServer,
            onWake = { wakeOnLAN.wake(it) },
        )
        AppTab.METRICS -> LicenseLocked(exceptDemo = true, demoOn = demoOn) {
            MetricsSection(fleet, history, board, panels,
                           bar = metricsBar, pushed = pushed)
        }
        AppTab.CONFIGURATOR -> LicenseLocked { ConfiguratorSection(
            model = configurator,
            scenarioID = wizardScenario,
            cloudflare = cloudflare,
            dnsCredentials = dnsCredentials,
            secrets = secrets,
            store = store,
            onPickScenario = onPickScenario,
            onInstall = onInstall,
            onOpenArtifact = onOpenArtifact,
        ) }
        AppTab.VPN -> LicenseLocked(exceptDemo = true, demoOn = demoOn) {
            VPNSection(fleet, vpnClients, pushed = pushed, tunnel = vpnTunnel,
                       onChangeRealitySite = onChangeRealitySite,
                       onRenewRealityKey = onRenewRealityKey)
        }
        AppTab.CONTAINERS -> LicenseLocked(exceptDemo = true, demoOn = demoOn) { ContainersSection(fleet, containers) }
        AppTab.SETTINGS ->
            SettingsSection(tabs, store, fleet, cloudflare, dnsCredentials,
                            secrets = secrets, appUpdates = appUpdates, pushed = pushed)
        AppTab.TERMINAL -> LicenseLocked { TerminalTab(fleet, terminals, terminalHosts, shellUsers) }
        else -> NotBuiltYet(tab)
    }
}
