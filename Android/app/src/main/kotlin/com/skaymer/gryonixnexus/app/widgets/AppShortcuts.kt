package com.skaymer.gryonixnexus.app.widgets

import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.MainActivity

/** The launcher shortcuts for the servers opened last */
class AppShortcuts(private val context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun opened(serverID: String) {
        val next = ShortcutPlan.remember(recent(), serverID)
        prefs.edit().putString(KEY, next.joinToString(SEPARATOR)).apply()
        publish()
    }

    fun publish() {
        val manager = context.getSystemService(ShortcutManager::class.java) ?: return
        val servers = FleetSnapshotStore(context).read()?.servers.orEmpty()
        val chosen = ShortcutPlan.servers(recent(), servers)
        runCatching { manager.dynamicShortcuts = chosen.map(::shortcut) }
    }

    private fun recent(): List<String> =
        prefs.getString(KEY, null)?.split(SEPARATOR)?.filter { it.isNotBlank() }.orEmpty()

    private fun shortcut(server: FleetSnapshot.Server): ShortcutInfo {
        val intent = ShortcutTarget.intent(ShortcutTarget.Server(server.id))
            .setClass(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return ShortcutInfo.Builder(context, "server_${server.id}")
            .setShortLabel(server.name)
            .setIcon(Icon.createWithResource(context, R.drawable.tab_icon_logo))
            .setIntent(intent)
            .build()
    }

    private companion object {
        const val PREFS = "launcher-shortcuts"
        const val KEY = "recent"
        const val SEPARATOR = ","
    }
}
