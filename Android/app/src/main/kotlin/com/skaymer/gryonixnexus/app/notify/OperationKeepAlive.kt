package com.skaymer.gryonixnexus.app.notify

import android.app.Notification
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/** Keeps the app running while an operation's notification is up */
class OperationKeepAlive : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!lead()) stopSelf()
        return START_NOT_STICKY
    }

    /** Puts the oldest running notification in front, or stops */
    @Synchronized
    fun lead(): Boolean {
        val (id, notification) = OperationNotices.oldestOngoing() ?: return false.also { leading = null }
        if (id == leading) return true
        val started = runCatching {
            ServiceCompat.startForeground(this, id, notification, foregroundType())
        }.isSuccess
        leading = id.takeIf { started }
        return started
    }

    /** Lets a finishing notification go before its last post */
    @Synchronized
    fun release(id: Int) {
        if (id != leading) return
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_DETACH)
        leading = null
        if (!lead()) stopSelf()
    }

    private var leading: Int? = null

    private fun foregroundType(): Int =
        if (Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0

    companion object {
        @Volatile
        private var instance: OperationKeepAlive? = null

        /** Starts or refreshes the service for running notifications */
        fun follow(context: Context) {
            val running = instance
            if (running != null) {
                running.lead()
                return
            }
            runCatching { ContextCompat.startForegroundService(context, Intent(context, OperationKeepAlive::class.java)) }
        }

        fun release(id: Int) {
            instance?.release(id)
        }
    }
}
