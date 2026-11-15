package com.skaymer.gryonixnexus.app.widgets

import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.servercontrol.AudioHubParser
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/** Plays or pauses the first audio hub in the fleet */
class AudioHubTileService : TileService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var busy = false

    private val app: GryonixApplication? get() = application as? GryonixApplication

    private fun hub(): Deployment? =
        runCatching { app?.fleet?.deployments?.value }.getOrNull()
            ?.firstOrNull { ServiceID.ODIO in it.services && it.usesAgent }

    override fun onStartListening() {
        super.onStartListening()
        redraw(null)
    }

    override fun onClick() {
        super.onClick()
        val deployment = hub() ?: return
        val app = app ?: return
        if (busy) return
        busy = true
        scope.launch {
            val result = runCatching {
                val players = AudioHubParser.players(app.odio(deployment, "GET", "/players"))
                val player = players.firstOrNull { it.isPlaying } ?: players.first()
                app.odio(deployment, "POST", "/players/${player.busName}/play_pause")
                !player.isPlaying
            }
            busy = false
            redraw(result.getOrNull())
        }
    }

    private fun redraw(playing: Boolean?) {
        val tile = qsTile ?: return
        val deployment = hub()
        tile.label = getString(R.string.tile_audio_hub)
        tile.icon = Icon.createWithResource(this, R.drawable.tile_icon_music)
        tile.state = when {
            deployment == null -> Tile.STATE_UNAVAILABLE
            playing == true -> Tile.STATE_ACTIVE
            else -> Tile.STATE_INACTIVE
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = deployment?.name ?: getString(R.string.tile_audio_hub_none)
        }
        tile.updateTile()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
