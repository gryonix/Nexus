package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.agentcontrol.VPNClientDevice
import com.skaymer.gryonixnexus.app.ui.design.MenuCheckItem
import com.skaymer.gryonixnexus.app.ui.design.MenuHeader
import com.skaymer.gryonixnexus.app.ui.design.MenuValueRow
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.app.vpn.LastTunnel
import com.skaymer.gryonixnexus.app.vpn.LocalDNS
import com.skaymer.gryonixnexus.app.vpn.TunnelChoices
import com.skaymer.gryonixnexus.app.vpn.VPNClientsViewModel
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.launch

/** What the card's rows do when something is picked */
class ThisDeviceActions(
    val own: (Deployment, ServiceID) -> Unit,
    val other: (Deployment, ServiceID, VPNClientDevice) -> Unit,
    val changeDNS: suspend (Deployment, String, List<String>) -> Unit,
    /** Null when this phone keeps no pins */
    val changePin: PinChange? = null,
)

/** Server, protocol, configuration, DNS and endpoint, each a popup */
@Composable
fun ThisDeviceRows(
    profile: LastTunnel.Profile,
    servers: List<Deployment>,
    clients: VPNClientsViewModel,
    protocolsOf: (Deployment) -> List<ServiceID>,
    enabled: Boolean,
    actions: ThisDeviceActions,
    pinned: String? = null,
) {
    val server = servers.firstOrNull { it.id == profile.serverId }
    var devices by remember(profile.serverId, profile.protocol) { mutableStateOf(emptyList<VPNClientDevice>()) }
    var local by remember(profile.serverId) { mutableStateOf(LocalDNS()) }
    LaunchedEffect(server?.id, profile.protocol) {
        server ?: return@LaunchedEffect
        devices = clients.devicesOf(server, profile.protocol)
        clients.dnsDefaultsOf(server)?.let { local = LocalDNS(it.localAddress, it.localServices) }
    }
    ServerMenuRow(profile, servers, enabled) { picked ->
        TunnelChoices.landingProtocol(protocolsOf(picked), profile.protocol)?.let { actions.own(picked, it) }
    }
    if (server == null) {
        ValueRow(stringResource(R.string.vpn_pick_protocol), protocolName(profile.protocol), onClick = null)
        ValueRow(stringResource(R.string.vpn_config), TunnelChoices.configurationName(profile), onClick = null)
    } else {
        ProtocolMenuRow(profile, protocolsOf(server), enabled) { actions.own(server, it) }
        ConfigurationMenuRow(profile, server, devices, clients.ownClientId(server, profile.protocol), enabled, actions)
        val clientId = TunnelChoices.clientId(profile, clients.ownClientId(server, profile.protocol))
        val scope = rememberCoroutineScope()
        var wanted by remember(profile.serverId, profile.protocol) { mutableStateOf<List<String>?>(null) }
        TunnelChoices.dns(devices, clientId)?.let { dns ->
            DNSMenuRow(wanted ?: dns, local, enabled) { chosen ->
                val idle = wanted == null
                wanted = chosen
                if (idle) {
                    scope.launch {
                        var applied: List<String>? = null
                        while (wanted != null && wanted != applied) {
                            val next = wanted!!
                            actions.changeDNS(server, clientId.orEmpty(), next)
                            applied = next
                        }
                        devices = clients.devicesOf(server, profile.protocol)
                        wanted = null
                    }
                }
            }
        }
    }
    TunnelChoices.endpoint(profile)?.let { EndpointRow(profile, it, pinned, enabled, actions.changePin) }
}

@Composable
private fun ServerMenuRow(
    profile: LastTunnel.Profile,
    servers: List<Deployment>,
    enabled: Boolean,
    onPick: (Deployment) -> Unit,
) {
    val title = stringResource(R.string.vpn_pick_server)
    if (servers.isEmpty()) {
        ValueRow(title, profile.server, onClick = null)
        return
    }
    MenuValueRow(title, profile.server, enabled) { close ->
        servers.forEach { server ->
            MenuCheckItem(server.name, server.id == profile.serverId) {
                close()
                if (server.id != profile.serverId) onPick(server)
            }
        }
    }
}

@Composable
private fun ProtocolMenuRow(
    profile: LastTunnel.Profile,
    protocols: List<ServiceID>,
    enabled: Boolean,
    onPick: (ServiceID) -> Unit,
) {
    MenuValueRow(stringResource(R.string.vpn_pick_protocol), protocolName(profile.protocol), enabled) { close ->
        protocols.forEach { protocol ->
            MenuCheckItem(protocolName(protocol), protocol == profile.protocol) {
                close()
                if (protocol != profile.protocol) onPick(protocol)
            }
        }
    }
}

@Composable
private fun ConfigurationMenuRow(
    profile: LastTunnel.Profile,
    server: Deployment,
    devices: List<VPNClientDevice>,
    ownId: String?,
    enabled: Boolean,
    actions: ThisDeviceActions,
) {
    val protocol = profile.protocol
    val others = TunnelChoices.others(devices, ownId)
    MenuValueRow(stringResource(R.string.vpn_config), TunnelChoices.configurationName(profile), enabled) { close ->
        MenuCheckItem(
            stringResource(R.string.vpn_own_configuration),
            TunnelChoices.isOwnInUse(profile, server.id, protocol, ownId),
        ) { close(); actions.own(server, protocol) }
        if (others.isNotEmpty()) MenuHeader(stringResource(R.string.vpn_other_configurations))
        others.forEach { device ->
            MenuCheckItem(device.name, TunnelChoices.isInUse(profile, server.id, protocol, device.id)) {
                close()
                actions.other(server, protocol, device)
            }
        }
    }
}

private fun protocolName(id: ServiceID): String =
    ServiceRegistry.service(id)?.displayName ?: id.rawValue
