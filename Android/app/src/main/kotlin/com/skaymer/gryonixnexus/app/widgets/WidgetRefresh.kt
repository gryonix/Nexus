package com.skaymer.gryonixnexus.app.widgets

import android.content.Context
import androidx.glance.appwidget.updateAll
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** Redraws every placed widget from the snapshot */
object WidgetRefresh {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    fun reload(context: Context) {
        val app = context.applicationContext
        scope.launch {
            runCatching {
                FleetHealthWidget().updateAll(app)
                SecurityWidget().updateAll(app)
                BackupsWidget().updateAll(app)
                UpdatesWidget().updateAll(app)
                ServerLoadWidget().updateAll(app)
                VPNStatusWidget().updateAll(app)
                DevicesWidget().updateAll(app)
            }
        }
    }
}

/** How long the tunnel has been up, as "1:02:03" */
object TunnelClock {
    fun text(since: Long, now: Long = System.currentTimeMillis()): String {
        val seconds = ((now - since) / 1000).coerceAtLeast(0)
        val hours = seconds / 3_600
        val minutes = (seconds % 3_600) / 60
        val rest = seconds % 60
        return if (hours > 0) "%d:%02d:%02d".format(hours, minutes, rest) else "%d:%02d".format(minutes, rest)
    }
}
