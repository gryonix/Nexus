package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.profile.ProxyTunnelText
import com.skaymer.gryonixnexus.servercontrol.Deployment

/** This phone's VLESS configuration fetched again after a new key */
suspend fun VpnTunnel.refreshReality(server: Deployment, clients: VPNClientsViewModel) {
    val stored = lastTunnel?.load() ?: return
    if (stored.serverId != server.id || stored.protocol != ServiceID.XRAY_REALITY || stored.clientId.isEmpty()) return
    val configuration = clients.configuration(server, ServiceID.XRAY_REALITY, stored.clientId) ?: return
    val text = ProxyTunnelText.compose(configuration.text, configuration.dns)
    if (state.value is VpnTunnel.State.Up) {
        connect(stored.device, text, stored.protocol, stored.server,
            choice = TunnelChoice(stored.serverId, stored.clientId, stored.clientName))
    } else {
        lastTunnel?.save(stored.copy(configuration = text))
    }
}
