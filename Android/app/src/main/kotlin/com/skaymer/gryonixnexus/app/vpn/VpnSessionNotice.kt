package com.skaymer.gryonixnexus.app.vpn

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

/** Whether the connection notification is shown, and its protocol names */
class VpnSessionNoticeSettings(private val store: SettingsStore) {
    private val _isEnabled = MutableStateFlow(store.boolean(KEY) ?: true)
    val isEnabled: StateFlow<Boolean> = _isEnabled.asStateFlow()

    private val _labels = MutableStateFlow(
        ServiceID.VPN_PROTOCOLS.associate { it.rawValue to store.string(labelKey(it)).orEmpty() }
            .filterValues { it.isNotBlank() },
    )
    /** The user's own protocol names, by service id */
    val labels: StateFlow<Map<String, String>> = _labels.asStateFlow()

    fun setEnabled(enabled: Boolean) {
        store.setBoolean(KEY, enabled)
        _isEnabled.value = enabled
    }

    fun setLabel(protocol: ServiceID, label: String) {
        val kept = label.take(LABEL_LENGTH)
        store.setString(labelKey(protocol), kept)
        _labels.value = (_labels.value + (protocol.rawValue to kept)).filterValues { it.isNotBlank() }
    }

    companion object {
        const val KEY = "vpn.sessionNotice"
        /** Characters a protocol name may have */
        const val LABEL_LENGTH = 8

        private fun labelKey(protocol: ServiceID) = "$KEY.label.${protocol.rawValue}"
    }
}

/** The ongoing notification while this device's tunnel is up */
class VpnSessionNotice(
    private val context: Context,
    private val tunnel: VpnTunnel,
    private val settings: VpnSessionNoticeSettings,
) {
    fun follow(scope: CoroutineScope) {
        scope.launch {
            combine(tunnel.session, settings.isEnabled, settings.labels) { session, shown, labels ->
                session.takeIf { shown }?.let { it to labels }
            }.collect { shown ->
                if (shown == null) hide() else show(shown.first, shown.second)
            }
        }
    }

    private fun show(session: VpnTunnel.Session, labels: Map<String, String>) {
        val allowed = Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (!allowed) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL,
                context.getString(R.string.vpn_session_notice_title),
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
        val text = content(session, context.getString(R.string.vpn_session_connected), labels)
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.tab_icon_logo)
            .setContentTitle(text.title)
            .setContentText(text.body)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setWhen(session.startedAt)
            .setUsesChronometer(true)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setContentIntent(openApp())
            .build()
        NotificationManagerCompat.from(context).notify(ID, notification)
    }

    private fun openApp(): PendingIntent? {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            ?: return null
        return PendingIntent.getActivity(context, ID, intent, PendingIntent.FLAG_IMMUTABLE)
    }

    private fun hide() {
        NotificationManagerCompat.from(context).cancel(ID)
    }

    data class Text(val title: String, val body: String)

    companion object {
        const val CHANNEL = "vpn-session"
        private const val ID = 4207

        /** Title names the server, body the protocol */
        fun content(session: VpnTunnel.Session, connected: String, labels: Map<String, String> = emptyMap()): Text {
            val own = labels[session.protocol.rawValue]?.trim()?.take(VpnSessionNoticeSettings.LABEL_LENGTH)
            val protocol = own?.takeIf { it.isNotEmpty() } ?: protocolName(session.protocol)
            val title = if (session.server.isBlank()) connected else "$connected · ${session.server}"
            return Text(title, protocol)
        }

        fun protocolName(id: ServiceID): String =
            ServiceRegistry.service(id)?.displayName ?: id.rawValue
    }
}
