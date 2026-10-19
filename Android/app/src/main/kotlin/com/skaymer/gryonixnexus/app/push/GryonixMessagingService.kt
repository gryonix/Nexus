package com.skaymer.gryonixnexus.app.push

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
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.notify.AlertAction
import com.skaymer.gryonixnexus.app.notify.ServerJobCard
import com.skaymer.gryonixnexus.app.notify.ServerJobNotices
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** Shows the server alerts gryonixPush sends */
class GryonixMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val gnx = message.data["gnx"]
        val data = AlertAction.data(gnx)
        val kind = data?.get("kind")?.jsonPrimitive?.contentOrNull.orEmpty()
        if (kind == LIVE_KIND) {
            val server = data?.get("server_id")?.jsonPrimitive?.contentOrNull.orEmpty()
            val card = runCatching { data?.get("live")?.jsonObject }.getOrNull()?.let(ServerJobCard::from) ?: return
            ServerJobNotices.received(server, card)
            return
        }
        val title = message.data["title"] ?: return
        val body = message.data["body"].orEmpty()
        show(this, title, body, (title + body).hashCode(), AlertAction.verbs(kind), gnx)
    }

    override fun onNewToken(token: String) {
        getSharedPreferences(PREFERENCES, MODE_PRIVATE).edit().putString(TOKEN_KEY, token).apply()
        (application as? com.skaymer.gryonixnexus.app.GryonixApplication)?.syncNotifyEverywhere()
    }

    companion object {
        const val CHANNEL = "server-alerts"
        const val PREFERENCES = "push"
        const val TOKEN_KEY = "fcm.token"
        const val LIVE_KIND = "gnx.live"

        fun show(
            context: Context,
            title: String,
            body: String,
            id: Int,
            verbs: List<AlertAction.Verb> = emptyList(),
            gnx: String? = null,
        ) {
            val allowed = Build.VERSION.SDK_INT < 33 ||
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
            if (!allowed) return
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, context.getString(R.string.push_channel), NotificationManager.IMPORTANCE_HIGH),
            )
            val builder = NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.tab_icon_logo)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setAutoCancel(true)
                .setContentIntent(openApp(context))
            verbs.forEach { builder.addAction(button(context, it, id, gnx.orEmpty())) }
            NotificationManagerCompat.from(context).notify(id, builder.build())
        }

        private fun button(context: Context, verb: AlertAction.Verb, id: Int, gnx: String): NotificationCompat.Action {
            val intent = Intent(context, AlertActionReceiver::class.java)
                .setAction(verb.id)
                .putExtra(AlertActionReceiver.EXTRA_DATA, gnx)
                .putExtra(AlertActionReceiver.EXTRA_NOTIFICATION, id)
            val pending = PendingIntent.getBroadcast(
                context, id * 31 + verb.ordinal, intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val label = when (verb) {
                AlertAction.Verb.BLOCK -> R.string.alert_action_block
                AlertAction.Verb.RESTART -> R.string.alert_action_restart
            }
            return NotificationCompat.Action.Builder(0, context.getString(label), pending)
                .setAuthenticationRequired(true)
                .build()
        }

        private fun openApp(context: Context): PendingIntent? {
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                ?: return null
            return PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE)
        }
    }
}
