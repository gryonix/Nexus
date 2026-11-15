package com.skaymer.gryonixnexus.app.widgets

import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.MainActivity
import com.skaymer.gryonixnexus.app.vpn.VpnTunnel

/** The VPN switch in the quick settings panel */
class VpnTileService : TileService() {
    private val tunnel: VpnTunnel? get() = (application as? GryonixApplication)?.vpnTunnel

    override fun onStartListening() {
        super.onStartListening()
        redraw()
    }

    override fun onClick() {
        super.onClick()
        val tunnel = tunnel ?: return openApp()
        when (tunnel.state.value) {
            is VpnTunnel.State.Up, is VpnTunnel.State.Working -> tunnel.disconnect()
            else -> {
                val saved = tunnel.lastTunnel?.load()
                if (saved == null || VpnService.prepare(this) != null) return openApp()
                tunnel.connect(saved.device, saved.configuration, saved.protocol, saved.server, remember = false)
            }
        }
        redraw()
    }

    private fun redraw() {
        val tile = qsTile ?: return
        val state = tunnel?.state?.value
        tile.state = when (state) {
            is VpnTunnel.State.Up, is VpnTunnel.State.Working -> Tile.STATE_ACTIVE
            else -> Tile.STATE_INACTIVE
        }
        tile.label = getString(R.string.widget_vpn)
        tile.icon = Icon.createWithResource(this, R.drawable.tab_icon_globe)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = WidgetPresentation.tunnelTitle(this, TunnelFeedState.of(state))
        }
        tile.updateTile()
    }

    private fun openApp() {
        val intent = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE))
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}

/** The widget's word for the tunnel's state */
object TunnelFeedState {
    fun of(state: VpnTunnel.State?): TunnelSnapshot.State = when (state) {
        is VpnTunnel.State.Up -> TunnelSnapshot.State.CONNECTED
        is VpnTunnel.State.Working -> TunnelSnapshot.State.CONNECTING
        is VpnTunnel.State.Failed -> TunnelSnapshot.State.FAILED
        else -> TunnelSnapshot.State.OFF
    }
}
