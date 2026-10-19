package com.skaymer.gryonixnexus.app.notify

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.annotation.StringRes
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.servercontrol.Deployment
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Long server actions as ongoing notifications */
object OperationNotices {
    const val CHANNEL = "server-operations"
    /** Outcomes: heard once, unlike the quiet progress */
    const val RESULTS_CHANNEL = "server-operation-results"
    const val RETRY_ACTION = "com.skaymer.gryonixnexus.RETRY_OPERATION"
    const val STOP_ACTION = "com.skaymer.gryonixnexus.STOP_OPERATION"
    const val EXTRA_NOTICE = "notice"
    private const val FIRST_ID = 6000

    @Volatile
    private var context: Context? = null
    private val nextID = AtomicInteger(FIRST_ID)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /** Cancels a server's agent runs begun after the given time */
    @Volatile
    var agentStopper: (suspend (Deployment, Long) -> Unit)? = null

    /** What the settings currently allow */
    @Volatile
    var display: () -> OperationDisplay = { OperationDisplay() }

    fun install(context: Context) {
        this.context = context.applicationContext
    }

    /** The last readable line of streamed output */
    fun lastLine(chunk: String): String =
        chunk.lineSequence().map { it.trim() }.lastOrNull { it.isNotEmpty() }.orEmpty()

    /** A localized line; empty when not installed */
    fun text(@StringRes id: Int, vararg args: Any): String = context?.getString(id, *args).orEmpty()

    /** Shows a notification; silent when not installed or off */
    fun start(
        @StringRes title: Int,
        vararg args: Any,
        server: String,
        text: String = "",
        kind: OperationKind = OperationKind.OTHER,
    ): OperationNotice = startTitled(context?.getString(title, *args).orEmpty(), server, text, kind)

    /** The same, for a title that is already text */
    fun startTitled(
        title: String,
        server: String,
        text: String = "",
        kind: OperationKind = OperationKind.OTHER,
    ): OperationNotice {
        val app = context?.takeIf { display().shows(kind) } ?: return OperationNotice(null, 0, "", server)
        val notice = OperationNotice(app, nextID.incrementAndGet(), title, server)
        busyServers.add(server)
        notice.post(text, null, running = true)
        return notice
    }

    /** Servers with an action this device started and still shows */
    internal val busyServers: MutableSet<String> = java.util.Collections.synchronizedSet(mutableSetOf())

    fun isShowing(server: String): Boolean = server in busyServers

    /** What "Try again" runs, by notification id */
    internal val retries: MutableMap<Int, () -> Unit> = java.util.concurrent.ConcurrentHashMap()

    /** Runs a failed action again from its notification */
    fun retry(notice: Int) {
        val again = retries.remove(notice) ?: return
        context?.let { NotificationManagerCompat.from(it).cancel(notice) }
        again()
    }

    /** What "Stop" runs, by notification id */
    internal val stops: MutableMap<Int, suspend () -> Unit> = ConcurrentHashMap()

    /** Notifications that are still running, by id */
    internal val running: MutableMap<Int, OperationNotice> = ConcurrentHashMap()

    /** A tap on "Stop" of a running action */
    fun stop(notice: Int) {
        running[notice]?.stopTapped()
    }

    internal fun launch(block: suspend () -> Unit) {
        scope.launch { block() }
    }

    internal fun launchAfter(millis: Long, block: () -> Unit) {
        scope.launch {
            delay(millis)
            block()
        }
    }
}

/** Receives the "Stop" button of a running action */
class OperationStopReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        OperationNotices.stop(intent.getIntExtra(OperationNotices.EXTRA_NOTICE, -1))
    }
}

/** Receives the "Try again" button of a failed action */
class OperationRetryReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        OperationNotices.retry(intent.getIntExtra(OperationNotices.EXTRA_NOTICE, -1))
    }
}

/** One action's notification, updated until it finishes */
class OperationNotice internal constructor(
    private val context: Context?,
    private val id: Int,
    private val title: String,
    private val server: String,
) {
    private var lastUpdate = 0L
    /** The newest state, waiting for the next redraw */
    private var pending: Pair<String, Double?>? = null
    private var flushPlanned = false
    private var isFinished = false
    private var isStopping = false
    private var shownText = ""
    private var shownProgress: Double? = null
    private val stopAsk = StopAsk()

    /** Offers "Stop" on this notification until it finishes */
    @Synchronized
    fun onStop(handler: suspend () -> Unit) {
        if (context == null || isFinished) return
        OperationNotices.stops[id] = handler
        OperationNotices.running[id] = this
        redraw()
    }

    /** Offers "Stop" for the server's agent runs started from now */
    fun stopsAgentJobs(deployment: Deployment) {
        val stopper = OperationNotices.agentStopper
        if (!deployment.usesAgent || stopper == null) return
        val since = System.currentTimeMillis()
        onStop { stopper(deployment, since) }
    }

    @Synchronized
    internal fun stopTapped() {
        val handler = OperationNotices.stops[id]
        if (handler == null || isFinished || isStopping) return
        when (stopAsk.tap(System.currentTimeMillis())) {
            StopAsk.Tap.ASK -> {
                redraw()
                OperationNotices.launchAfter(StopAsk.WINDOW_MILLIS) { redraw() }
            }
            StopAsk.Tap.STOP -> {
                isStopping = true
                redraw()
                OperationNotices.launch { runCatching { handler() }.onFailure { stopFailed() } }
            }
        }
    }

    @Synchronized
    private fun stopFailed() {
        isStopping = false
        redraw()
    }

    @Synchronized
    private fun redraw() {
        if (!isFinished) post(shownText, shownProgress, running = true)
    }

    /** Redraws at most every two seconds, the newest state last */
    @Synchronized
    fun update(text: String, progress: Double? = null) {
        if (isFinished) return
        pending = text to progress
        val wait = UPDATE_MILLIS - (System.currentTimeMillis() - lastUpdate)
        if (wait <= 0) return sendPending()
        if (flushPlanned) return
        flushPlanned = true
        OperationNotices.launchAfter(wait) { flush() }
    }

    @Synchronized
    private fun flush() {
        flushPlanned = false
        sendPending()
    }

    private fun sendPending() {
        val next = pending ?: return
        if (isFinished) return
        pending = null
        lastUpdate = System.currentTimeMillis()
        post(next.first, next.second, running = true)
    }

    @Synchronized
    fun finish(text: String, error: String? = null, retry: (() -> Unit)? = null) {
        if (isFinished) return
        isFinished = true
        OperationNotices.stops.remove(id)
        OperationNotices.running.remove(id)
        OperationNotices.busyServers.remove(server)
        if (error != null && retry != null) OperationNotices.retries[id] = retry
        post(error ?: text, null, running = false, failed = error != null)
    }

    internal fun post(text: String, progress: Double?, running: Boolean, failed: Boolean = false) {
        val context = context ?: return
        if (!allowed(context)) return
        channel(context)
        if (running) {
            shownText = text
            shownProgress = progress
        }
        val channel = if (running) OperationNotices.CHANNEL else OperationNotices.RESULTS_CHANNEL
        val builder = NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.tab_icon_logo)
            .setContentTitle(title)
            .setContentText(if (running) displayedText(text) else text)
            .setSubText(server.ifBlank { null })
            .setOngoing(running)
            .setOnlyAlertOnce(true)
            .setAutoCancel(!running)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setContentIntent(openApp(context))
        if (running) {
            val percent = progress?.let { (it.coerceIn(0.0, 1.0) * 100).toInt() }
            builder.setProgress(100, percent ?: 0, percent == null)
            if (id in OperationNotices.stops && !isStopping) {
                builder.addAction(0, context.getString(R.string.notice_stop), stopIntent(context))
            }
        } else if (failed) {
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(text))
            if (id in OperationNotices.retries) {
                builder.addAction(0, context.getString(R.string.notice_retry), retryIntent(context))
            }
        } else {
            builder.setTimeoutAfter(FINISHED_LINGER_MILLIS)
        }
        NotificationManagerCompat.from(context).notify(id, builder.build())
    }

    private fun allowed(context: Context): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun channel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                OperationNotices.CHANNEL,
                context.getString(R.string.operations_channel),
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
        manager.createNotificationChannel(
            NotificationChannel(
                OperationNotices.RESULTS_CHANNEL,
                context.getString(R.string.operation_results_channel),
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
    }

    private fun displayedText(text: String): String = when {
        isStopping -> context?.getString(R.string.notice_stopping).orEmpty()
        stopAsk.isAsking(System.currentTimeMillis()) -> context?.getString(R.string.notice_stop_ask).orEmpty()
        else -> text
    }

    private fun stopIntent(context: Context): PendingIntent {
        val intent = Intent(context, OperationStopReceiver::class.java)
            .setAction(OperationNotices.STOP_ACTION)
            .putExtra(OperationNotices.EXTRA_NOTICE, id)
        return PendingIntent.getBroadcast(context, id, intent, PendingIntent.FLAG_IMMUTABLE)
    }

    private fun retryIntent(context: Context): PendingIntent {
        val intent = Intent(context, OperationRetryReceiver::class.java)
            .setAction(OperationNotices.RETRY_ACTION)
            .putExtra(OperationNotices.EXTRA_NOTICE, id)
        return PendingIntent.getBroadcast(context, id, intent, PendingIntent.FLAG_IMMUTABLE)
    }

    private fun openApp(context: Context): PendingIntent? {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            ?: return null
        return PendingIntent.getActivity(context, id, intent, PendingIntent.FLAG_IMMUTABLE)
    }

    private companion object {
        const val UPDATE_MILLIS = 2_000L
        const val FINISHED_LINGER_MILLIS = 30_000L
    }
}
