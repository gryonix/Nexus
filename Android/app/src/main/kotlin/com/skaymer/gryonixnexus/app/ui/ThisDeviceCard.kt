package com.skaymer.gryonixnexus.app.ui

import android.app.Activity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.agentcontrol.VPNClientDevice
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.app.vpn.EndpointPin
import com.skaymer.gryonixnexus.app.vpn.EndpointPinStore
import com.skaymer.gryonixnexus.app.vpn.EndpointPins
import com.skaymer.gryonixnexus.app.vpn.LastTunnel
import com.skaymer.gryonixnexus.app.vpn.TunnelChoice
import com.skaymer.gryonixnexus.app.vpn.TunnelChoices
import com.skaymer.gryonixnexus.app.vpn.VPNClientsViewModel
import com.skaymer.gryonixnexus.app.vpn.VpnTunnel
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.launch

/** A tunnel to start and the server device it uses */
data class TunnelStart(
    val fileName: String,
    val text: String,
    val protocol: ServiceID,
    val serverName: String,
    val choice: TunnelChoice?,
    /** What a proxy link cannot carry itself */
    val dns: List<String> = emptyList(),
) {
    /** Proxies keep their DNS beside the link */
    val tunnelText: String
        get() = if (protocol == ServiceID.SHADOWSOCKS || protocol == ServiceID.XRAY_REALITY) {
            com.skaymer.gryonixnexus.profile.ProxyTunnelText.compose(text, dns)
        } else {
            text
        }
}

/** Starts a tunnel after the system VPN consent */
@Composable
fun rememberTunnelStarter(tunnel: VpnTunnel): (TunnelStart) -> Unit {
    var pending by remember { mutableStateOf<TunnelStart?>(null) }
    val askPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { result ->
        val start = pending
        pending = null
        if (result.resultCode == Activity.RESULT_OK && start != null) tunnel.start(start)
    }
    return { start ->
        val consent = tunnel.permissionRequest()
        if (consent == null) {
            tunnel.start(start)
        } else {
            pending = start
            askPermission.launch(consent)
        }
    }
}

private fun VpnTunnel.start(start: TunnelStart) =
    connect(start.fileName, start.tunnelText, start.protocol, start.serverName, choice = start.choice)

/** This phone's tunnel: state, configuration and a picker */
@Composable
fun ThisDeviceCard(
    tunnel: VpnTunnel,
    servers: List<Deployment>,
    clients: VPNClientsViewModel,
) {
    val state by tunnel.state.collectAsState()
    var picks by remember { mutableStateOf(0) }
    val profile = remember(state, picks) { tunnel.lastTunnel?.load() }
    val pinned = remember(profile, picks) { profile?.let { tunnel.endpointPins?.pinnedEndpoint(it) } }
    val start = rememberTunnelStarter(tunnel)
    val actions = rememberThisDeviceActions(tunnel, clients, profile, start) { picks++ }
    var choosing by remember { mutableStateOf(false) }
    val idle = state !is VpnTunnel.State.Working

    GroupedSection(
        header = stringResource(R.string.vpn_this_device),
        footer = pinned?.let { stringResource(R.string.vpn_pinned_footer, it) },
    ) {
        GroupedRow(trailing = { ConnectButton(state, profile, start, tunnel::disconnect) }) {
            RowLabel(title = stateTitle(state), subtitle = (state as? VpnTunnel.State.Failed)?.message)
        }
        profile?.let { chosen ->
            ThisDeviceRows(chosen, servers, clients, { TunnelChoices.protocols(it, tunnel::canCarry) }, idle, actions, pinned)
        }
        ActionRow(
            text = stringResource(R.string.vpn_choose_config),
            enabled = idle && servers.isNotEmpty(),
            onClick = { choosing = true },
            showDivider = false,
        )
    }

    if (choosing) {
        TunnelConfigurationSheet(
            tunnel, servers, clients, profile,
            onOwn = actions.own,
            onOther = actions.other,
            onClose = { choosing = false },
        )
    }
}

/** What the card's rows call, wired to this tunnel */
@Composable
private fun rememberThisDeviceActions(
    tunnel: VpnTunnel,
    clients: VPNClientsViewModel,
    profile: LastTunnel.Profile?,
    start: (TunnelStart) -> Unit,
    picked: () -> Unit,
): ThisDeviceActions {
    val choose = rememberChooser(tunnel, start, picked)
    val scope = rememberCoroutineScope()
    return ThisDeviceActions(
        own = { server, protocol ->
            scope.launch { useOwn(clients, choose, server, protocol, TunnelChoices.carriedDNS(profile)) }
        },
        other = { server, protocol, device -> scope.launch { useOther(clients, choose, server, protocol, device) } },
        changeDNS = { server, clientId, dns -> profile?.let { changeDNS(clients, choose, it, server, clientId, dns) } },
        changePin = tunnel.endpointPins?.let { pins ->
            { chosen, pin -> changePin(tunnel, pins, start, chosen, pin); picked() }
        },
    )
}

/** Stores or drops the pin, restarting a running tunnel */
private fun changePin(
    tunnel: VpnTunnel,
    pins: EndpointPinStore,
    start: (TunnelStart) -> Unit,
    profile: LastTunnel.Profile,
    pin: EndpointPin?,
) {
    val key = EndpointPins.key(profile)
    if (pin == null) pins.remove(key) else pins.save(key, pin)
    val stored = tunnel.lastTunnel?.load() ?: return
    if (tunnel.state.value is VpnTunnel.State.Up && EndpointPins.key(stored) == key) start(restartOf(stored))
}

/** The stored tunnel, started again as it is */
private fun restartOf(profile: LastTunnel.Profile): TunnelStart {
    val choice = TunnelChoice(profile.serverId, profile.clientId, profile.clientName)
    return TunnelStart(profile.device, profile.configuration, profile.protocol, profile.server, choice)
}

/** Switches a running tunnel over; otherwise only remembers the pick */
@Composable
private fun rememberChooser(tunnel: VpnTunnel, start: (TunnelStart) -> Unit, picked: () -> Unit): (TunnelStart) -> Unit =
    { next ->
        if (tunnel.state.value is VpnTunnel.State.Up) {
            start(next)
        } else {
            tunnel.keep(next)
            picked()
        }
    }

/** Changes the device's DNS on its server, then here */
private suspend fun changeDNS(
    clients: VPNClientsViewModel,
    choose: (TunnelStart) -> Unit,
    profile: LastTunnel.Profile,
    server: Deployment,
    clientId: String,
    dns: List<String>,
) {
    if (clientId.isEmpty()) return
    val configuration = clients.changeDNS(server, profile.protocol, clientId, dns) ?: return
    val choice = TunnelChoice(server.id, profile.clientId, profile.clientName)
    val next = TunnelStart(profile.device, configuration.text, profile.protocol, server.name, choice, configuration.dns)
    choose(next)
}

/** Remembers a tunnel for the next Connect without starting it */
private fun VpnTunnel.keep(start: TunnelStart) {
    val choice = start.choice
    lastTunnel?.save(
        LastTunnel.Profile(
            start.fileName, start.tunnelText, start.protocol, start.serverName,
            choice?.serverId.orEmpty(), choice?.clientId.orEmpty(), choice?.clientName.orEmpty(),
        ),
    )
}

private suspend fun useOwn(
    clients: VPNClientsViewModel,
    choose: (TunnelStart) -> Unit,
    server: Deployment,
    protocol: ServiceID,
    dns: List<String> = emptyList(),
) {
    val label = android.os.Build.MODEL ?: "Android"
    val configuration = clients.thisDeviceConfiguration(server, protocol, label, dns) ?: return
    val choice = TunnelChoice(server.id, "", label)
    choose(TunnelStart(configuration.fileName, configuration.text, protocol, server.name, choice, configuration.dns))
}

private suspend fun useOther(
    clients: VPNClientsViewModel,
    choose: (TunnelStart) -> Unit,
    server: Deployment,
    protocol: ServiceID,
    device: VPNClientDevice,
) {
    val configuration = clients.configuration(server, protocol, device.id) ?: return
    val choice = TunnelChoice(server.id, device.id, device.name)
    choose(TunnelStart(configuration.fileName, configuration.text, protocol, server.name, choice, configuration.dns))
}

@Composable
private fun stateTitle(state: VpnTunnel.State): String = when (state) {
    is VpnTunnel.State.Up -> stringResource(R.string.vpn_connected_as, state.device)
    is VpnTunnel.State.Working -> stringResource(R.string.vpn_working)
    else -> stringResource(R.string.vpn_not_connected)
}

@Composable
private fun ConnectButton(
    state: VpnTunnel.State,
    profile: LastTunnel.Profile?,
    start: (TunnelStart) -> Unit,
    onDisconnect: () -> Unit,
) {
    when (state) {
        is VpnTunnel.State.Up, is VpnTunnel.State.Working ->
            PlainButton(text = stringResource(R.string.vpn_disconnect), onClick = onDisconnect, danger = true)
        else -> if (profile != null) {
            PlainButton(text = stringResource(R.string.vpn_connect), onClick = { start(restartOf(profile)) })
        }
    }
}

/** Server, then protocol, then which configuration this phone uses */
@Composable
private fun TunnelConfigurationSheet(
    tunnel: VpnTunnel,
    servers: List<Deployment>,
    clients: VPNClientsViewModel,
    profile: LastTunnel.Profile?,
    onOwn: (Deployment, ServiceID) -> Unit,
    onOther: (Deployment, ServiceID, VPNClientDevice) -> Unit,
    onClose: () -> Unit,
) {
    val devices = remember { mutableStateOf<Map<String, List<VPNClientDevice>>>(emptyMap()) }
    LaunchedEffect(servers) {
        servers.forEach { server ->
            TunnelChoices.protocols(server, tunnel::canCarry).forEach { protocol ->
                val listed = clients.devicesOf(server, protocol)
                devices.value = devices.value + (key(server, protocol) to listed)
            }
        }
    }
    IOSSheet(
        title = stringResource(R.string.vpn_this_device),
        onClose = onClose,
        closeLabel = stringResource(R.string.close),
    ) {
        servers.forEach { server ->
            TunnelChoices.protocols(server, tunnel::canCarry).forEach { protocol ->
                val ownId = clients.ownClientId(server, protocol)
                val others = TunnelChoices.others(devices.value[key(server, protocol)].orEmpty(), ownId)
                val heading = "${server.name} · ${protocolName(protocol)}"
                GroupedSection(header = heading) {
                    CheckRow(
                        title = stringResource(R.string.vpn_own_configuration),
                        checked = TunnelChoices.isOwnInUse(profile, server.id, protocol, ownId),
                        onClick = { onOwn(server, protocol); onClose() },
                        showDivider = false,
                    )
                }
                if (others.isNotEmpty()) {
                    OtherConfigurations(server, protocol, profile, others, onOther, onClose)
                }
            }
        }
    }
}

@Composable
private fun OtherConfigurations(
    server: Deployment,
    protocol: ServiceID,
    profile: LastTunnel.Profile?,
    others: List<VPNClientDevice>,
    onOther: (Deployment, ServiceID, VPNClientDevice) -> Unit,
    onClose: () -> Unit,
) {
    GroupedSection(header = stringResource(R.string.vpn_other_configurations)) {
        others.forEach { device ->
            CheckRow(
                title = device.name,
                checked = TunnelChoices.isInUse(profile, server.id, protocol, device.id),
                onClick = { onOther(server, protocol, device); onClose() },
                showDivider = device != others.last(),
            )
        }
    }
}

private fun key(server: Deployment, protocol: ServiceID) = "${server.id}|${protocol.rawValue}"

private fun protocolName(id: ServiceID): String =
    ServiceRegistry.service(id)?.displayName ?: id.rawValue
