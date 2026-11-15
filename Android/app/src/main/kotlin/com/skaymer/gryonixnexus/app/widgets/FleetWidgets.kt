package com.skaymer.gryonixnexus.app.widgets

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalContext
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.provideContent
import androidx.glance.layout.Column
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.text.FontWeight
import com.skaymer.gryonixnexus.R

/** The server picked for a placed widget */
private val LocalChosenServer = compositionLocalOf<String?> { null }

/** A widget drawn from the snapshot */
abstract class SnapshotWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snapshot = FleetSnapshotStore(context).read()
        val widget = runCatching { GlanceAppWidgetManager(context).getAppWidgetId(id) }.getOrNull()
        val server = widget?.let { WidgetServerChoice(context).server(it) }
        provideContent {
            CompositionLocalProvider(LocalChosenServer provides server) {
                GlanceTheme { Content(snapshot) }
            }
        }
    }

    override suspend fun onDelete(context: Context, glanceId: GlanceId) {
        runCatching { GlanceAppWidgetManager(context).getAppWidgetId(glanceId) }
            .onSuccess { WidgetServerChoice(context).forget(intArrayOf(it)) }
    }

    @Composable
    abstract fun Content(snapshot: FleetSnapshot?)

    /** The picked server with the reading, else the first */
    @Composable
    protected fun chosen(snapshot: FleetSnapshot?, has: (FleetSnapshot.Server) -> Boolean) =
        WidgetServerChoice.pick(snapshot, LocalChosenServer.current, has)

    companion object {
        /** The widget class behind a placed widget id */
        fun forWidget(context: Context, widget: Int): SnapshotWidget? {
            val provider = android.appwidget.AppWidgetManager.getInstance(context).getAppWidgetInfo(widget)?.provider
            return when (provider?.className) {
                SecurityReceiver::class.java.name -> SecurityWidget()
                BackupsReceiver::class.java.name -> BackupsWidget()
                UpdatesReceiver::class.java.name -> UpdatesWidget()
                ServerLoadReceiver::class.java.name -> ServerLoadWidget()
                else -> null
            }
        }
    }
}

class FleetHealthWidget : SnapshotWidget() {
    @Composable
    override fun Content(snapshot: FleetSnapshot?) {
        val context = LocalContext.current
        val title = context.getString(R.string.widget_fleet)
        if (snapshot == null || snapshot.serversWithServiceReadings.isEmpty()) {
            return UnavailableCard(title, snapshot != null)
        }
        val attention = snapshot.servicesNeedingAttention
        val detail = listOfNotNull(
            context.getString(R.string.widget_services_on, snapshot.totalServices, snapshot.serversWithServiceReadings.size),
            snapshot.unreachableServerCount.takeIf { it > 0 }?.let { context.getString(R.string.widget_unreachable, it) },
        ).joinToString(" · ")
        StatusCard(
            WidgetPresentation.fleet(snapshot), title,
            if (attention == 0) context.getString(R.string.widget_all_well) else context.getString(R.string.widget_need_attention, attention),
            detail, WidgetPresentation.age(context, snapshot.oldestReadingAt),
        )
    }
}

class SecurityWidget : SnapshotWidget() {
    @Composable
    override fun Content(snapshot: FleetSnapshot?) {
        val context = LocalContext.current
        val title = context.getString(R.string.widget_security)
        val server = chosen(snapshot) { it.security != null }
        val security = server?.security ?: return UnavailableCard(title, snapshot != null)
        val detail = when {
            !security.isPresent -> server.name
            !security.isGuarding -> context.getString(R.string.widget_not_blocking)
            else -> context.getString(R.string.widget_banned, security.localBans, server.name)
        }
        StatusCard(
            WidgetPresentation.security(security), title,
            if (security.isPresent) context.getString(R.string.widget_attacks, security.alertsLast24h)
            else context.getString(R.string.widget_not_set_up),
            detail, WidgetPresentation.age(context, security.takenAt),
        )
    }
}

class BackupsWidget : SnapshotWidget() {
    @Composable
    override fun Content(snapshot: FleetSnapshot?) {
        val context = LocalContext.current
        val title = context.getString(R.string.widget_backups)
        val backups = chosen(snapshot) { it.backups != null }?.backups ?: return UnavailableCard(title, snapshot != null)
        val detail = when {
            !backups.isOn -> context.getString(R.string.widget_no_auto_backup)
            backups.servicesCovered == 0 -> context.getString(R.string.widget_no_services_chosen)
            else -> context.getString(R.string.widget_services_keeps, backups.servicesCovered, backups.retention)
        }
        StatusCard(
            WidgetPresentation.backups(backups), title, WidgetPresentation.cadence(context, backups),
            detail, WidgetPresentation.age(context, backups.takenAt),
        )
    }
}

class UpdatesWidget : SnapshotWidget() {
    @Composable
    override fun Content(snapshot: FleetSnapshot?) {
        val context = LocalContext.current
        val title = context.getString(R.string.widget_updates)
        val server = chosen(snapshot) { it.updates != null }
        val updates = server?.updates ?: return UnavailableCard(title, snapshot != null)
        StatusCard(
            WidgetPresentation.updates(updates), title,
            if (updates.waiting == 0) context.getString(R.string.widget_up_to_date)
            else context.getString(R.string.widget_waiting, updates.waiting),
            context.getString(R.string.widget_checked, updates.checked, server.name),
            WidgetPresentation.age(context, updates.takenAt),
        )
    }
}

class ServerLoadWidget : SnapshotWidget() {
    @Composable
    override fun Content(snapshot: FleetSnapshot?) {
        val context = LocalContext.current
        val server = chosen(snapshot) { it.metrics != null }
        val reading = server?.metrics
            ?: return UnavailableCard(context.getString(R.string.widget_load), snapshot != null, R.string.widget_open_dashboard_once)
        WidgetFrame {
            Column(GlanceModifier.fillMaxSize()) {
                WidgetText(server.name, size = 14.sp, weight = FontWeight.Bold)
                WidgetText(listOfNotNull(reading.machineLabel.takeIf { it != server.name && it.isNotEmpty() },
                    WidgetPresentation.age(context, reading.takenAt)).joinToString(" · "), size = 11.sp, secondary = true)
                Spacer(GlanceModifier.height(6.dp))
                LoadBar(context.getString(R.string.widget_cpu), reading.cpuPercent)
                Spacer(GlanceModifier.height(4.dp))
                LoadBar(context.getString(R.string.widget_memory), reading.memoryPercent)
                Spacer(GlanceModifier.height(4.dp))
                LoadBar(context.getString(R.string.widget_disk), reading.diskPercent)
                if (server.failure != null) {
                    WidgetText(context.getString(R.string.widget_last_failed), size = 11.sp, color = WidgetPresentation.ORANGE)
                }
            }
        }
    }
}

class VPNStatusWidget : SnapshotWidget() {
    @Composable
    override fun Content(snapshot: FleetSnapshot?) {
        val context = LocalContext.current
        val tunnel = snapshot?.tunnel ?: TunnelSnapshot()
        val tint = when (tunnel.state) {
            TunnelSnapshot.State.CONNECTED -> WidgetPresentation.GREEN
            TunnelSnapshot.State.FAILED -> WidgetPresentation.RED
            TunnelSnapshot.State.CONNECTING -> WidgetPresentation.ORANGE
            TunnelSnapshot.State.OFF -> null
        }
        WidgetFrame {
            Column(GlanceModifier.fillMaxSize()) {
                WidgetText(context.getString(R.string.widget_vpn), secondary = true)
                Spacer(GlanceModifier.height(4.dp))
                WidgetText(WidgetPresentation.tunnelTitle(context, tunnel.state), size = 16.sp, weight = FontWeight.Bold, color = tint)
                tunnel.since?.takeIf { tunnel.isActive }?.let { since ->
                    WidgetText(TunnelClock.text(since), size = 18.sp)
                }
                tunnel.subtitle?.let { WidgetText(it, size = 11.sp, secondary = true) }
                Spacer(GlanceModifier.defaultWeight())
                when {
                    snapshot == null -> WidgetText(context.getString(R.string.widget_open_app), size = 11.sp, secondary = true)
                    tunnel.profileCount == 0 -> WidgetText(context.getString(R.string.widget_no_tunnel), size = 11.sp, secondary = true)
                }
            }
        }
    }
}

class DevicesWidget : SnapshotWidget() {
    @Composable
    override fun Content(snapshot: FleetSnapshot?) {
        val context = LocalContext.current
        WidgetFrame {
            Column(GlanceModifier.fillMaxSize()) {
                WidgetText("${snapshot?.deviceCount ?: 0} " + context.getString(R.string.widget_devices_word), size = 14.sp, weight = FontWeight.Bold)
                Spacer(GlanceModifier.height(6.dp))
                val servers = snapshot?.servers.orEmpty()
                if (servers.isEmpty()) {
                    WidgetText(context.getString(if (snapshot != null) R.string.widget_no_servers else R.string.widget_open_app), secondary = true)
                }
                servers.take(4).forEach { server ->
                    WidgetText("${server.name} · ${server.deviceCount}" + if (server.failure != null) " ⚠" else "", size = 13.sp)
                }
                Spacer(GlanceModifier.defaultWeight())
                snapshot?.let { WidgetText(context.getString(R.string.widget_read_at, WidgetPresentation.age(context, it.generatedAt).orEmpty()), size = 11.sp, secondary = true) }
            }
        }
    }
}

class FleetHealthReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = FleetHealthWidget() }
class SecurityReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = SecurityWidget() }
class BackupsReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = BackupsWidget() }
class UpdatesReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = UpdatesWidget() }
class ServerLoadReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = ServerLoadWidget() }
class VPNStatusReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = VPNStatusWidget() }
class DevicesReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = DevicesWidget() }
