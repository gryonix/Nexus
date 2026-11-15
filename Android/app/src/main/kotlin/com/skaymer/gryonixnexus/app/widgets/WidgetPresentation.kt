package com.skaymer.gryonixnexus.app.widgets

import android.content.Context
import androidx.compose.ui.graphics.Color
import com.skaymer.gryonixnexus.R

/** How a widget judges and words its reading */
object WidgetPresentation {
    enum class Verdict { WELL, ATTENTION, BAD, UNKNOWN }

    fun tint(verdict: Verdict): Color? = when (verdict) {
        Verdict.WELL -> GREEN
        Verdict.ATTENTION -> ORANGE
        Verdict.BAD -> RED
        Verdict.UNKNOWN -> null
    }

    fun fleet(snapshot: FleetSnapshot): Verdict = when {
        snapshot.serversWithServiceReadings.isEmpty() -> Verdict.UNKNOWN
        snapshot.unreachableServerCount > 0 -> Verdict.BAD
        snapshot.servicesNeedingAttention > 0 -> Verdict.ATTENTION
        else -> Verdict.WELL
    }

    fun security(summary: FleetSnapshot.SecuritySummary?): Verdict = when {
        summary == null -> Verdict.UNKNOWN
        !summary.isPresent -> Verdict.ATTENTION
        summary.isGuarding -> Verdict.WELL
        else -> Verdict.BAD
    }

    fun backups(summary: FleetSnapshot.BackupsSummary?): Verdict = when {
        summary == null -> Verdict.UNKNOWN
        summary.isOn && summary.servicesCovered > 0 -> Verdict.WELL
        else -> Verdict.ATTENTION
    }

    fun updates(summary: FleetSnapshot.UpdatesSummary?): Verdict = when {
        summary == null -> Verdict.UNKNOWN
        summary.waiting > 0 -> Verdict.ATTENTION
        else -> Verdict.WELL
    }

    /** "Now", "5 min ago", "3 h ago", "2 d ago" */
    fun age(context: Context, takenAt: Long?, now: Long = System.currentTimeMillis()): String? {
        takenAt ?: return null
        val seconds = (now - takenAt) / 1000
        return when {
            seconds < 60 -> context.getString(R.string.widget_now)
            seconds < 3_600 -> context.getString(R.string.widget_min_ago, seconds / 60)
            seconds < 86_400 -> context.getString(R.string.widget_h_ago, seconds / 3_600)
            else -> context.getString(R.string.widget_d_ago, seconds / 86_400)
        }
    }

    fun cadence(context: Context, summary: FleetSnapshot.BackupsSummary): String {
        val hours = summary.everyHours
        val days = summary.everyDays
        return when {
            !summary.isOn -> context.getString(R.string.widget_off)
            hours == 1 -> context.getString(R.string.widget_hourly)
            hours != null -> context.getString(R.string.widget_every_hours, hours)
            days == 1 -> context.getString(R.string.widget_daily)
            days != null -> context.getString(R.string.widget_every_days, days)
            else -> context.getString(R.string.widget_on)
        }
    }

    fun percent(value: Double?): String = value?.let { "${Math.round(it)}%" } ?: "—"

    /** Green below 70, orange below 90, red above */
    fun loadTint(percent: Double?): Color? = when {
        percent == null -> null
        percent < 70 -> GREEN
        percent < 90 -> ORANGE
        else -> RED
    }

    fun tunnelTitle(context: Context, state: TunnelSnapshot.State): String = context.getString(
        when (state) {
            TunnelSnapshot.State.OFF -> R.string.widget_tunnel_off
            TunnelSnapshot.State.CONNECTING -> R.string.widget_tunnel_connecting
            TunnelSnapshot.State.CONNECTED -> R.string.widget_tunnel_connected
            TunnelSnapshot.State.FAILED -> R.string.widget_tunnel_failed
        },
    )

    val GREEN = Color(0xFF34C759)
    val ORANGE = Color(0xFFFF9500)
    val RED = Color(0xFFFF3B30)
}
