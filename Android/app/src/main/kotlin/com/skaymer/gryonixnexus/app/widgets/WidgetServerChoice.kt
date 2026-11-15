package com.skaymer.gryonixnexus.app.widgets

import android.content.Context

/** The server each placed widget shows, by widget id */
class WidgetServerChoice(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun server(widget: Int): String? = prefs.getString(key(widget), null)

    fun choose(widget: Int, server: String?) {
        prefs.edit().apply { if (server == null) remove(key(widget)) else putString(key(widget), server) }.apply()
    }

    fun forget(widgets: IntArray) {
        prefs.edit().apply { widgets.forEach { remove(key(it)) } }.apply()
    }

    private fun key(widget: Int) = "widget.$widget"

    companion object {
        private const val PREFS = "widget-servers"

        /** The chosen server with the reading, else the first */
        fun pick(
            snapshot: FleetSnapshot?,
            chosen: String?,
            has: (FleetSnapshot.Server) -> Boolean,
        ): FleetSnapshot.Server? {
            val servers = snapshot?.servers.orEmpty().filter(has)
            return servers.firstOrNull { it.id == chosen } ?: servers.firstOrNull()
        }

        /** Servers worth offering in the picker */
        fun choices(snapshot: FleetSnapshot?): List<FleetSnapshot.Server> =
            snapshot?.servers.orEmpty().filter { it.hasAnyReading }
    }
}
