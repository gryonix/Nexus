package com.skaymer.gryonixnexus.app.widgets

import com.skaymer.gryonixnexus.app.vpn.VpnTunnel
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

/** Keeps the widgets' tunnel line in step with the tunnel */
object TunnelFeed {
    fun follow(scope: CoroutineScope, tunnel: VpnTunnel) {
        scope.launch {
            combine(tunnel.state, tunnel.session) { state, session -> snapshot(tunnel, state, session) }
                .distinctUntilChanged()
                .collect { WidgetFeed.tunnel(it) }
        }
    }

    private fun snapshot(tunnel: VpnTunnel, state: VpnTunnel.State, session: VpnTunnel.Session?): TunnelSnapshot {
        val saved = tunnel.lastTunnel?.load()
        val shown = TunnelFeedState.of(state)
        return TunnelSnapshot(
            state = shown,
            since = session?.startedAt?.takeIf { it > 0 && shown == TunnelSnapshot.State.CONNECTED },
            profileName = (state as? VpnTunnel.State.Up)?.device ?: saved?.device,
            serverName = session?.server?.ifEmpty { null } ?: saved?.server?.ifEmpty { null },
            protocolName = (session?.protocol ?: saved?.protocol)?.let { ServiceRegistry.service(it)?.displayName },
            profileCount = if (saved != null) 1 else 0,
        )
    }
}
