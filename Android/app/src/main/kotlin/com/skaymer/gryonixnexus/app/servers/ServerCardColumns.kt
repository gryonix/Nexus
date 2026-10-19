package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.servercontrol.ServerCardSize

enum class ServerCardColumns(val raw: String) {
    ONE("one"),

    /** Two half-width cards per row */
    TWO("two");

    /** The per-server size this setting stands for */
    val cardSize: ServerCardSize
        get() = if (this == ONE) ServerCardSize.WIDE else ServerCardSize.COMPACT

    companion object {
        const val KEY = "servers.cardColumns"

        fun of(raw: String?): ServerCardColumns = entries.firstOrNull { it.raw == raw } ?: ONE
    }
}
