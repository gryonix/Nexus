package com.skaymer.gryonixnexus.app.widgets

import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.MainActivity
import com.skaymer.gryonixnexus.app.shell.AppTab

/** The server overview in the quick settings panel */
class ServerStatusTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        redraw()
    }

    override fun onClick() {
        super.onClick()
        val intent = ShortcutTarget.intent(ShortcutTarget.Tab(AppTab.SERVERS))
            .setClass(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(PendingIntent.getActivity(this, 1, intent, PendingIntent.FLAG_IMMUTABLE))
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    private fun redraw() {
        val tile = qsTile ?: return
        val model = ServerTileModel.of(FleetSnapshotStore(this).read())
        tile.state = if (model.active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = getString(R.string.tile_server_status)
        tile.icon = Icon.createWithResource(this, R.drawable.tab_icon_globe)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = when {
                !model.hasReadings -> getString(R.string.widget_nothing_read)
                model.active -> getString(R.string.widget_all_well)
                else -> getString(R.string.widget_need_attention, model.attention)
            }
        }
        tile.updateTile()
    }
}
