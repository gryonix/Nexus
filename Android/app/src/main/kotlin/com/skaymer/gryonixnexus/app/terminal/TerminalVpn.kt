package com.skaymer.gryonixnexus.app.terminal

import android.content.Intent
import com.skaymer.gryonixnexus.app.vpn.LastTunnel
import com.skaymer.gryonixnexus.app.vpn.TunnelChoice
import com.skaymer.gryonixnexus.app.vpn.VpnTunnel
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.transport.TerminalEndpoint
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull

/** Turns the last tunnel on when no route answered */
class TerminalVpn(private val tunnel: VpnTunnel, private val last: LastTunnel) {
    val state: StateFlow<VpnTunnel.State> get() = tunnel.state

    /** The tunnel worth offering, if one would help */
    fun offer(deployment: Deployment, routes: List<TerminalEndpoint>): LastTunnel.Profile? {
        if (tunnel.runningDevice() != null) return null
        val profile = last.load() ?: return null
        val privateOnly = routes.isNotEmpty() && routes.all { TerminalRoutes.isPrivate(it.host) }
        return profile.takeIf { it.serverId == deployment.id || privateOnly }
    }

    /** What Android asks before the first tunnel, if anything */
    fun permissionRequest(): Intent? = tunnel.permissionRequest()

    /** True once the tunnel is up */
    suspend fun connect(profile: LastTunnel.Profile): Boolean {
        tunnel.connect(
            profile.device, profile.configuration, profile.protocol, profile.server, remember = false,
            choice = TunnelChoice(profile.serverId, profile.clientId, profile.clientName),
        )
        val settled = withTimeoutOrNull(CONNECT_WAIT_MS) {
            tunnel.state.first { it is VpnTunnel.State.Up || it is VpnTunnel.State.Failed }
        }
        return settled is VpnTunnel.State.Up
    }

    private companion object {
        const val CONNECT_WAIT_MS = 25_000L
    }
}
