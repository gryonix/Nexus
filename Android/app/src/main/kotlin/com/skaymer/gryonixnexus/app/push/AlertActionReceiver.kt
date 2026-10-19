package com.skaymer.gryonixnexus.app.push

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationManagerCompat
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.notify.AlertAction
import com.skaymer.gryonixnexus.app.notify.AlertOutcome
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/** Receives the buttons on a server alert */
class AlertActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val verb = AlertAction.Verb.entries.firstOrNull { it.id == intent.action } ?: return
        val action = AlertAction.data(intent.getStringExtra(EXTRA_DATA))?.let { AlertAction.from(verb, it) } ?: return
        val app = context.applicationContext as? GryonixApplication ?: return
        val notification = intent.getIntExtra(EXTRA_NOTIFICATION, 0)
        NotificationManagerCompat.from(context).cancel(notification)
        val pending = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val outcome = app.alertActions.run(action)
                GryonixMessagingService.show(context, action.host, text(context, outcome), notification)
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        const val EXTRA_DATA = "gnx"
        const val EXTRA_NOTIFICATION = "notification"

        fun text(context: Context, outcome: AlertOutcome): String = when (outcome) {
            is AlertOutcome.Blocked -> context.getString(R.string.alert_blocked, outcome.address)
            is AlertOutcome.Restarted -> context.getString(R.string.alert_restarted, outcome.name)
            is AlertOutcome.Gone -> context.getString(R.string.alert_gone, outcome.name)
            AlertOutcome.UnknownServer -> context.getString(R.string.alert_unknown_server)
            is AlertOutcome.Failed -> context.getString(R.string.alert_failed, outcome.reason)
        }
    }
}
