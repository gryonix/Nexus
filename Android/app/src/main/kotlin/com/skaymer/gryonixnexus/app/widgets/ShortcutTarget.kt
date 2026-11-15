package com.skaymer.gryonixnexus.app.widgets

import android.content.Intent
import com.skaymer.gryonixnexus.app.shell.AppTab

/** Where a launcher shortcut or tile sends the app */
sealed interface ShortcutTarget {
    data class Tab(val tab: AppTab) : ShortcutTarget

    data class Server(val id: String) : ShortcutTarget

    companion object {
        const val ACTION = "com.skaymer.gryonixnexus.OPEN"
        const val EXTRA_TAB = "tab"
        const val EXTRA_SERVER = "server"

        fun of(action: String?, tab: String?, server: String?): ShortcutTarget? {
            if (action != ACTION) return null
            server?.takeIf { it.isNotBlank() }?.let { return Server(it) }
            return tab?.let(AppTab::of)?.let(::Tab)
        }

        fun of(intent: Intent?): ShortcutTarget? =
            of(intent?.action, intent?.getStringExtra(EXTRA_TAB), intent?.getStringExtra(EXTRA_SERVER))

        fun intent(target: ShortcutTarget): Intent = Intent(ACTION).apply {
            when (target) {
                is Tab -> putExtra(EXTRA_TAB, target.tab.key)
                is Server -> putExtra(EXTRA_SERVER, target.id)
            }
        }
    }
}

/** Which servers get a launcher shortcut, and in what order */
object ShortcutPlan {
    const val LIMIT = 4

    fun servers(recent: List<String>, all: List<FleetSnapshot.Server>, limit: Int = LIMIT): List<FleetSnapshot.Server> {
        val byId = all.associateBy { it.id }
        val ordered = recent.mapNotNull { byId[it] } + all.filter { it.id !in recent }
        return ordered.take(limit)
    }

    fun remember(recent: List<String>, opened: String, limit: Int = LIMIT): List<String> =
        (listOf(opened) + recent.filter { it != opened }).take(limit)
}

/** What the server tile shows */
data class ServerTileModel(val active: Boolean, val attention: Int, val hasReadings: Boolean) {
    companion object {
        fun of(snapshot: FleetSnapshot?): ServerTileModel {
            val verdict = snapshot?.let(WidgetPresentation::fleet) ?: WidgetPresentation.Verdict.UNKNOWN
            return ServerTileModel(
                active = verdict == WidgetPresentation.Verdict.WELL,
                attention = snapshot?.servicesNeedingAttention ?: 0,
                hasReadings = verdict != WidgetPresentation.Verdict.UNKNOWN,
            )
        }
    }
}
