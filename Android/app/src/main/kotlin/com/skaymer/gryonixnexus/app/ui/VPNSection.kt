package com.skaymer.gryonixnexus.app.ui

import com.skaymer.gryonixnexus.app.vpn.PublicDNS

import android.app.Activity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.ui.text.font.FontFamily
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.MenuValueRow
import com.skaymer.gryonixnexus.app.ui.design.MenuCheckItem
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material.icons.filled.PowerSettingsNew
import com.skaymer.gryonixnexus.app.ui.design.DisclosureChevron
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.IOSSegmentedControl
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.R
import androidx.compose.material.icons.outlined.AddCircleOutline
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.agentcontrol.VPNClientConfiguration
import com.skaymer.gryonixnexus.agentcontrol.VPNClientDevice
import com.skaymer.gryonixnexus.agentcontrol.VPNClientProtocols
import com.skaymer.gryonixnexus.app.servers.FleetRepository
import com.skaymer.gryonixnexus.app.vpn.AdvancedVpnStore
import com.skaymer.gryonixnexus.app.vpn.TunnelChoice
import com.skaymer.gryonixnexus.app.vpn.VPNAccess
import com.skaymer.gryonixnexus.app.vpn.VPNClientsState
import com.skaymer.gryonixnexus.app.vpn.VPNClientsViewModel
import com.skaymer.gryonixnexus.app.vpn.VPNMoveViewModel
import com.skaymer.gryonixnexus.app.vpn.VpnSessionNotice
import com.skaymer.gryonixnexus.app.vpn.refreshReality
import com.skaymer.gryonixnexus.app.vpn.VpnSessionNoticeSettings
import com.skaymer.gryonixnexus.app.vpn.VpnTunnel
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.services.XrayRealityService
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.launch

@Composable
fun VPNSection(
    fleet: FleetRepository,
    clients: VPNClientsViewModel,
    /** This device's own tunnel */
    tunnel: VpnTunnel? = null,
    only: String? = null,
    pushed: PushedScreen? = null,
    onChangeRealitySite: (Deployment, String) -> Unit = { _, _ -> },
    onRenewRealityKey: (Deployment, suspend () -> Unit) -> Unit = { _, _ -> },
    advanced: AdvancedVpnStore? = null,
) {
    val allDeployments by fleet.deployments.collectAsState()
    val deployments = remember(allDeployments, only) {
        if (only == null) allDeployments else allDeployments.filter { it.id == only }
    }
    val manageable = remember(deployments) { VPNAccess.manageable(deployments) }
    val panelOnly = remember(deployments) { VPNAccess.panelOnly(deployments) }

    if (manageable.isEmpty() && panelOnly.isEmpty() && (tunnel == null || only != null)) {
        EmptySection(R.string.vpn_no_vpn, R.string.vpn_no_vpn_hint)
        return
    }

    var openServerID by rememberSaveable { mutableStateOf<String?>(null) }
    var advancedOpen by rememberSaveable { mutableStateOf(false) }
    if (advancedOpen && advanced != null && tunnel != null) {
        val start = rememberTunnelStarter(tunnel)
        AdvancedVpnScreen(
            store = advanced,
            onApply = { text -> start(TunnelStart("Advanced", text, ServiceID.XRAY_REALITY, "Advanced", null)) },
            onClose = { advancedOpen = false },
        )
        return
    }
    val opened = remember(manageable, openServerID, only) {
        if (only != null) manageable.firstOrNull()
        else manageable.firstOrNull { it.id == openServerID }
    }

    if (opened != null) {
        if (only == null) {
            BackHandler { openServerID = null }
            DisposableEffect(opened.id) {
                pushed?.push(opened.name) { openServerID = null }
                onDispose { pushed?.clear() }
            }
        }
        ServerDevices(opened, clients, tunnel, onChangeRealitySite, onRenewRealityKey)
        return
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        if (tunnel != null && (only == null || manageable.isNotEmpty())) {
            item { ThisDeviceCard(tunnel, manageable, clients) }
        }
        if (manageable.isNotEmpty()) {
            item {
                GroupedSection(
                    header = stringResource(R.string.vpn_servers_title),
                    note = stringResource(R.string.vpn_servers_hint),
                ) {
                    manageable.forEach { deployment ->
                        GroupedRow(
                            showDivider = deployment != manageable.last(),
                            onClick = { openServerID = deployment.id },
                            trailing = { DisclosureChevron() },
                        ) {
                            RowLabel(
                                title = deployment.name,
                                subtitle = VPNClientProtocols.installed(deployment.services)
                                    .joinToString(" · ") { protocolName(it) },
                            )
                        }
                    }
                }
            }
        }
        if (panelOnly.isNotEmpty()) {
            item { PanelOnly(panelOnly) }
        }
        tunnel?.onDemand?.let { settings ->
            item { OnDemandSection(settings) }
        }
        tunnel?.noticeSettings?.let { settings ->
            item { SessionNoticeSection(settings) }
        }
        if (advanced != null && tunnel != null) {
            item { AdvancedVpnEntry { advancedOpen = true } }
        }
    }
}

/** Entry to the VPN Advanced module, at the bottom */
@Composable
private fun AdvancedVpnEntry(onOpen: () -> Unit) {
    GroupedSection {
        GroupedRow(
            showDivider = false,
            onClick = onOpen,
            leading = { Icon(Icons.Outlined.Tune, null, tint = Gryonix.colors.accent) },
            trailing = { DisclosureChevron() },
        ) {
            RowLabel(
                title = stringResource(R.string.module_vpn_advanced),
                subtitle = stringResource(R.string.module_vpn_advanced_note),
            )
        }
    }
}

/** The switch for the ongoing connection notification */
@Composable
private fun SessionNoticeSection(settings: VpnSessionNoticeSettings) {
    val shown by settings.isEnabled.collectAsState()
    GroupedSection(
        header = stringResource(R.string.vpn_session_notice_title),
        note = stringResource(R.string.vpn_session_notice_hint),
    ) {
        ToggleRow(
            title = stringResource(R.string.vpn_session_notice_toggle),
            checked = shown,
            onCheckedChange = settings::setEnabled,
            showDivider = false,
        )
    }
    ProtocolNamesSection(settings)
}

/** The user's own protocol names in the notification */
@Composable
private fun ProtocolNamesSection(settings: VpnSessionNoticeSettings) {
    val labels by settings.labels.collectAsState()
    val protocols = remember { ServiceID.VPN_PROTOCOLS.sortedBy { VpnSessionNotice.protocolName(it) } }
    GroupedSection(
        header = stringResource(R.string.vpn_session_notice_names),
        note = stringResource(R.string.vpn_session_notice_names_hint),
    ) {
        protocols.forEachIndexed { index, protocol ->
            FieldRow(
                label = VpnSessionNotice.protocolName(protocol),
                value = labels[protocol.rawValue].orEmpty(),
                onValueChange = { settings.setLabel(protocol, it) },
                placeholder = VpnSessionNotice.protocolName(protocol),
                showDivider = index < protocols.lastIndex,
            )
        }
    }
}

/** One server's devices: which protocol, then the devices of it */
@Composable
private fun ServerDevices(
    server: Deployment,
    clients: VPNClientsViewModel,
    tunnel: VpnTunnel?,
    onChangeRealitySite: (Deployment, String) -> Unit,
    onRenewRealityKey: (Deployment, suspend () -> Unit) -> Unit,
) {
    var protocolRaw by rememberSaveable(server.id) { mutableStateOf<String?>(null) }
    val protocol = remember(server, protocolRaw) {
        VPNAccess.protocol(protocolRaw?.let { ServiceID(it) }, server)
    }
    val installed = remember(server) { VPNClientProtocols.installed(server.services) }

    Column(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Devices(server, protocol, clients, tunnel, onChangeRealitySite, onRenewRealityKey, Modifier.weight(1f)) {
            ProtocolSection(installed, protocol) { protocolRaw = it.rawValue }
        }
    }
}

/** The devices of one protocol on one server */
@Composable
private fun Devices(
    server: Deployment,
    protocol: ServiceID,
    clients: VPNClientsViewModel,
    tunnel: VpnTunnel?,
    onChangeRealitySite: (Deployment, String) -> Unit,
    onRenewRealityKey: (Deployment, suspend () -> Unit) -> Unit,
    modifier: Modifier = Modifier,
    protocolPicker: @Composable () -> Unit = {},
) {
    LaunchedEffect(server.id, protocol.rawValue) { clients.load(server, protocol) }
    LaunchedEffect(server.id) {
        clients.loadDefaultDNS(server)
        clients.loadDNSPriority(server)
    }
    DisposableEffect(Unit) { onDispose { clients.stop() } }

    val state by clients.state.collectAsState()
    var comparing by remember { mutableStateOf(false) }
    var removing by remember { mutableStateOf<VPNClientDevice?>(null) }
    var showing by remember { mutableStateOf<Pair<VPNClientConfiguration, VPNClientDevice>?>(null) }
    var addingDevice by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    LazyColumn(
        modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(Metrics.sectionGap),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(top = 12.dp, bottom = 24.dp),
    ) {
        item { protocolPicker() }
        if (tunnel != null && tunnel.canCarry(protocol)) {
            item { TunnelRow(tunnel, server, protocol, clients) }
        }
        if (protocol == ServiceID.XRAY_REALITY) {
            item { RealitySiteSection(server, onChangeRealitySite) }
            item {
                RealityKeySection { onRenewRealityKey(server) { tunnel?.refreshReality(server, clients) } }
            }
        }
        item { DefaultDNSSection(server, state, clients, onCompare = { comparing = true }) }
        state.dnsPriority?.let { priority ->
            item { VPNDNSPrioritySection(server, clients, priority, state.localDNS) }
        }
        if (server.usesAgent) item { VPNSpeedRow(server) }
        if (VPNMoveViewModel.offers(server)) {
            item { VPNPlacementSection(server) }
        }
        item {
            DeviceList(
                state,
                onAdd = { addingDevice = true },
                onShow = { device ->
                    scope.launch { showing = clients.configuration(server, protocol, device.id)?.let { it to device } }
                },
                onRemove = { removing = it },
            )
        }
    }

    DeviceDialogs(server, protocol, clients, tunnel, state, removing, showing, comparing,
        onCloseRemoving = { removing = null }, onCloseShowing = { showing = null }, onCloseComparing = { comparing = false })
    if (addingDevice) AddDeviceSheet(server, protocol, state, clients) { addingDevice = false }
}

/** The DNS new devices get */
@Composable
private fun DefaultDNSSection(
    server: Deployment,
    state: VPNClientsState,
    clients: VPNClientsViewModel,
    onCompare: () -> Unit,
) {
    val local = state.localDNS
    GroupedSection(
        header = stringResource(R.string.dns_row),
        note = stringResource(R.string.dns_section_note),
        footer = if (local.isGone(state.defaultDNS)) stringResource(R.string.dns_local_gone) else null,
    ) {
        DNSRow(state.defaultDNS, onChoose = { clients.setDefaultDNS(server, it) }, local = local)
        ActionRow(
            text = stringResource(R.string.dns_compare),
            onClick = onCompare,
            showDivider = false,
            leading = { Icon(Icons.Outlined.Info, null, tint = Gryonix.colors.accent) },
        )
    }
}

/** A new device's name and DNS, on its own sheet */
@Composable
internal fun AddDeviceSheet(
    server: Deployment,
    protocol: ServiceID,
    state: VPNClientsState,
    clients: VPNClientsViewModel,
    onClose: () -> Unit,
) {
    var newName by rememberSaveable { mutableStateOf("") }
    var newDNS by remember(state.defaultDNS) { mutableStateOf(state.defaultDNS) }
    val proxy = protocol == ServiceID.SHADOWSOCKS || protocol == ServiceID.XRAY_REALITY
    IOSSheet(
        title = stringResource(R.string.vpn_new_device),
        onClose = onClose,
        closeLabel = stringResource(R.string.vpn_cancel),
        action = SheetAction(
            title = stringResource(R.string.vpn_add),
            enabled = newName.isNotBlank() && !state.isBusy,
            onSelect = {
                clients.add(server, protocol, newName.trim(), newDNS)
                onClose()
            },
        ),
    ) {
        GroupedSection(header = stringResource(R.string.name_label)) {
            FieldRow(
                label = stringResource(R.string.vpn_device_name),
                value = newName,
                onValueChange = { newName = it },
                showDivider = false,
            )
        }
        GroupedSection(
            footer = stringResource(
                when {
                    state.localDNS.isGone(newDNS) -> R.string.dns_local_gone
                    proxy -> R.string.dns_proxy_note
                    else -> R.string.dns_written_note
                },
            ),
        ) {
            DNSRow(newDNS, onChoose = { newDNS = it }, local = state.localDNS)
        }
    }
}

/** The devices, or why there are none yet */
@Composable
private fun DeviceList(
    state: VPNClientsState,
    onAdd: () -> Unit,
    onShow: (VPNClientDevice) -> Unit,
    onRemove: (VPNClientDevice) -> Unit,
) {
    if (!state.hasAnswered && state.isBusy) return DevicesLoading()
    GroupedSection(header = stringResource(R.string.vpn_devices), footer = state.errorMessage) {
        if (state.saysThereAreNone) {
            GroupedRow {
                Text(stringResource(R.string.vpn_no_devices), style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.secondaryLabel)
            }
        }
        state.devices.forEach { device -> DeviceRow(device, state, showDivider = true, onShow, onRemove) }
        ActionRow(
            text = stringResource(R.string.vpn_add_device),
            onClick = onAdd,
            showDivider = false,
            leading = { Icon(Icons.Outlined.AddCircleOutline, null, tint = Gryonix.colors.accent) },
        )
    }
}

@Composable
private fun DevicesLoading() {
    Row(
        Modifier.padding(horizontal = Metrics.listInset + 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = Gryonix.colors.tertiaryLabel)
        Text(
            stringResource(R.string.vpn_loading),
            style = MaterialTheme.typography.bodySmall,
            color = Gryonix.colors.secondaryLabel,
        )
    }
}

@Composable
private fun DeviceRow(
    device: VPNClientDevice,
    state: VPNClientsState,
    showDivider: Boolean,
    onShow: (VPNClientDevice) -> Unit,
    onRemove: (VPNClientDevice) -> Unit,
) {
    GroupedRow(
        onClick = { onShow(device) },
        showDivider = showDivider,
        trailing = {
            IconButton(onClick = { onRemove(device) }, modifier = Modifier.size(28.dp)) {
                Icon(
                    Icons.Filled.Delete,
                    contentDescription = stringResource(R.string.vpn_remove),
                    tint = Gryonix.colors.danger,
                    modifier = Modifier.size(18.dp),
                )
            }
        },
    ) {
        RowLabel(device.name, listOf(device.detail, dnsName(device.dns, state.localDNS)).joinToString(" · "))
    }
}

/** The confirmations and sheets the device list opens */
@Composable
private fun DeviceDialogs(
    server: Deployment,
    protocol: ServiceID,
    clients: VPNClientsViewModel,
    tunnel: VpnTunnel?,
    state: VPNClientsState,
    removing: VPNClientDevice?,
    showing: Pair<VPNClientConfiguration, VPNClientDevice>?,
    comparing: Boolean,
    onCloseRemoving: () -> Unit,
    onCloseShowing: () -> Unit,
    onCloseComparing: () -> Unit,
) {
    var changingDNS by remember { mutableStateOf<VPNClientDevice?>(null) }
    removing?.let { device ->
        ConfirmAlert(
            title = stringResource(R.string.vpn_remove_confirm, device.name),
            message = stringResource(R.string.vpn_remove_confirm_hint),
            confirm = stringResource(R.string.vpn_remove),
            cancel = stringResource(R.string.vpn_cancel),
            destructive = true,
            onConfirm = {
                clients.remove(server, protocol, device.id)
                onCloseRemoving()
            },
            onCancel = onCloseRemoving,
        )
    }
    showing?.let { (configuration, device) ->
        ConfigurationDialog(
            configuration = configuration,
            tunnel = tunnel?.takeIf { it.canCarry(protocol, configuration.text) },
            protocol = protocol,
            serverName = server.name,
            choice = TunnelChoice(server.id, device.id, device.name),
            onChangeDNS = {
                onCloseShowing()
                changingDNS = device
            },
            onClose = onCloseShowing,
        )
    }
    changingDNS?.let { device ->
        DNSPickerSheet(
            current = device.dns,
            local = state.localDNS,
            onChoose = { dns ->
                changingDNS = null
                clients.setDNS(server, protocol, device.id, dns)
            },
            onClose = { changingDNS = null },
        )
    }
    if (comparing) {
        PublicDNSSheet(PublicDNS.matching(state.defaultDNS)) { onCloseComparing() }
    }
}

/** One device's configuration, as text */
@Composable
private fun ConfigurationDialog(
    configuration: VPNClientConfiguration,
    tunnel: VpnTunnel?,
    /** Which datapath this configuration belongs to */
    protocol: ServiceID,
    serverName: String,
    choice: TunnelChoice,
    onChangeDNS: () -> Unit,
    onClose: () -> Unit,
) {
    val copySecret = rememberSecretClipboard()
    var copied by remember { mutableStateOf(false) }
    val state = tunnel?.state?.collectAsState()?.value
    val up = when (state) {
        is VpnTunnel.State.Up -> state.device == configuration.fileName
        is VpnTunnel.State.Working -> state.device == configuration.fileName
        else -> false
    }
    val start = tunnel?.let { rememberTunnelStarter(it) }
    IOSAlert(
        title = configuration.fileName,
        onDismiss = onClose,
        actions = buildList {
            add(AlertAction(stringResource(R.string.vpn_config_close), onSelect = onClose))
            add(AlertAction(stringResource(R.string.dns_change), onSelect = onChangeDNS))
            if (tunnel != null) {
                add(
                    AlertAction(
                        stringResource(
                            if (up) R.string.vpn_disconnect else R.string.vpn_connect
                        ),
                        onSelect = {
                            if (up) {
                                tunnel.disconnect()
                            } else {
                                start?.invoke(
                                    TunnelStart(
                                        configuration.fileName, configuration.text, protocol, serverName, choice,
                                        configuration.dns,
                                    ),
                                )
                            }
                        },
                    )
                )
            }
            add(
                AlertAction(
                    stringResource(
                        if (copied) R.string.vpn_config_copied else R.string.vpn_config_copy
                    ),
                    preferred = true,
                    onSelect = {
                        copySecret(configuration.text)
                        copied = true
                    },
                )
            )
        },
    ) {
        SelectionContainer {
            Column(Modifier.heightIn(max = 340.dp).verticalScroll(rememberScrollState())) {
                Text(
                    configuration.text,
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                    color = Gryonix.colors.label,
                )
            }
        }
    }
}

@Composable
private fun PanelOnly(servers: List<Deployment>) {
    val reason = remember(servers) { VPNAccess.panelReason(servers) }
    GroupedSection(
        header = stringResource(R.string.vpn_panel_only_title),
        footer = stringResource(
            when (reason) {
                VPNAccess.PanelReason.NO_AGENT -> R.string.vpn_panel_only_agent
                VPNAccess.PanelReason.BY_CHOICE -> R.string.vpn_panel_only_choice
                VPNAccess.PanelReason.MIXED -> R.string.vpn_panel_only_mixed
            }
        ),
        modifier = Modifier.padding(bottom = 16.dp),
    ) {
        servers.forEach { server ->
            GroupedRow(showDivider = server != servers.last()) {
                Text(
                    server.name,
                    style = MaterialTheme.typography.bodyLarge,
                    color = Gryonix.colors.label,
                )
            }
        }
    }
}

private fun protocolName(id: ServiceID): String =
    ServiceRegistry.service(id)?.displayName ?: id.rawValue

/** "Protocol — WireGuard ⇕" and "About WireGuard", as on iOS */
@Composable
private fun ProtocolSection(installed: List<ServiceID>, selected: ServiceID, onSelect: (ServiceID) -> Unit) {
    if (installed.size <= 1) return
    var about by remember { mutableStateOf<VPNProtocolInfo?>(null) }
    val info = VPNProtocolInfo.of(selected)
    GroupedSection(header = stringResource(R.string.vpn_pick_protocol), note = stringResource(R.string.vpn_protocol_note)) {
        MenuValueRow(stringResource(R.string.vpn_pick_protocol), protocolName(selected), showDivider = info != null) { close ->
            installed.forEach { id ->
                MenuCheckItem(protocolName(id), checked = id == selected) { close(); onSelect(id) }
            }
        }
        if (info != null) {
            ActionRow(
                text = stringResource(R.string.vpn_info_about, protocolName(selected)),
                onClick = { about = info },
                showDivider = false,
                leading = { Icon(Icons.Outlined.Info, null, tint = Gryonix.colors.accent) },
            )
        }
    }
    about?.let { VPNProtocolInfoSheet(it) { about = null } }
}

@Composable
private fun TunnelRow(
    tunnel: VpnTunnel,
    server: Deployment,
    protocol: ServiceID,
    clients: VPNClientsViewModel,
) {
    val state by tunnel.state.collectAsState()
    val scope = rememberCoroutineScope()
    val start = rememberTunnelStarter(tunnel)
    val connectHere: () -> Unit = {
        scope.launch {
            val label = android.os.Build.MODEL ?: "Android"
            val profile = clients.thisDeviceConfiguration(server, protocol, label)
                ?: return@launch
            val choice = TunnelChoice(server.id, "", label)
            start(TunnelStart(profile.fileName, profile.text, protocol, server.name, choice))
        }
    }
    val panelsClosed = protocol != ServiceID.WIREGUARD_VPN && ServiceID.VPN_PANEL in server.services
    val footer = (state as? VpnTunnel.State.Failed)?.message
        ?: if (panelsClosed) stringResource(R.string.vpn_panels_wireguard_only)
        else if (com.skaymer.gryonixnexus.app.servers.DemoDeployments.isDemoID(server.id)) stringResource(R.string.vpn_demo_unprotected)
        else null
    GroupedSection(header = stringResource(R.string.vpn_this_device), footer = footer) {
        when (val current = state) {
            is VpnTunnel.State.Up, is VpnTunnel.State.Working -> GroupedRow(
                showDivider = false,
                trailing = { TunnelRowAction(current, onConnect = connectHere, onDisconnect = tunnel::disconnect) },
            ) {
                RowLabel(
                    if (current is VpnTunnel.State.Up) stringResource(R.string.vpn_connected_as, current.device)
                    else stringResource(R.string.vpn_working),
                )
            }
            else -> ActionRow(
                text = stringResource(R.string.vpn_connect),
                onClick = connectHere,
                showDivider = false,
                leading = { Icon(Icons.Filled.PowerSettingsNew, null, tint = Gryonix.colors.accent) },
            )
        }
    }
}

@Composable
private fun TunnelRowAction(
    state: VpnTunnel.State,
    onConnect: () -> Unit,
    onDisconnect: () -> Unit,
) {
    when (state) {
        is VpnTunnel.State.Up, is VpnTunnel.State.Working ->
            PlainButton(
                text = stringResource(R.string.vpn_disconnect),
                onClick = onDisconnect,
                danger = true,
            )
        else -> PlainButton(text = stringResource(R.string.vpn_connect), onClick = onConnect)
    }
}

/** Gives VLESS / Reality a new server key */
@Composable
private fun RealityKeySection(onRenew: () -> Unit) {
    var asking by remember { mutableStateOf(false) }
    GroupedSection(
        header = stringResource(R.string.vpn_reality_key_title),
        note = stringResource(R.string.vpn_reality_key_hint),
    ) {
        ActionRow(
            text = stringResource(R.string.vpn_reality_new_key),
            onClick = { asking = true },
            showDivider = false,
        )
    }
    if (asking) {
        ConfirmAlert(
            title = stringResource(R.string.vpn_reality_new_key_ask),
            message = stringResource(R.string.vpn_reality_new_key_message),
            confirm = stringResource(R.string.vpn_reality_new_key_confirm),
            destructive = true,
            cancel = stringResource(R.string.actions_cancel),
            onConfirm = { asking = false; onRenew() },
            onCancel = { asking = false },
        )
    }
}

@Composable
private fun RealitySiteSection(server: Deployment, onChange: (Deployment, String) -> Unit) {
    val current = server.serviceSettings.xrayRealitySNI
    var site by rememberSaveable(server.id, current) { mutableStateOf(current) }
    val valid = XrayRealityService.normalisedSite(site)
    GroupedSection(
        header = stringResource(R.string.vpn_reality_site),
        note = stringResource(R.string.vpn_reality_site_hint),
    ) {
        XrayRealityService.SUGGESTED_SITES.forEach { candidate ->
            CheckRow(title = candidate, checked = site == candidate, onClick = { site = candidate })
        }
        FieldRow(
            label = stringResource(R.string.vpn_reality_other_site),
            value = site,
            onValueChange = { site = it },
            placeholder = "www.apple.com",
        )
        ActionRow(
            text = stringResource(R.string.vpn_reality_use_site),
            enabled = valid != null && valid != current,
            onClick = { valid?.let { onChange(server, it) } },
            showDivider = false,
        )
    }
}
