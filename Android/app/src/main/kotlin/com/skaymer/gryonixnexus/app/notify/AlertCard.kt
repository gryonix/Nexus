package com.skaymer.gryonixnexus.app.notify

import com.skaymer.gryonixnexus.R

/** A tapped alert about a problem, shown over its server */
data class AlertCard(val title: String, val body: String, val kind: String) {
    val advice: Int? get() = advice(kind)

    /** The screen the advice names, if any */
    val screen: Int? get() = when (kind) {
        "gnx.alert.raid", "gnx.alert.smart" -> R.string.storage_section
        "gnx.alert.backup" -> R.string.backups
        "gnx.alert.load", "gnx.alert.memory" -> R.string.processes_title
        else -> null
    }

    companion object {
        /** Only a problem with advice gets a card */
        fun from(kind: String, title: String?, body: String?): AlertCard? {
            if (title.isNullOrEmpty() || advice(kind) == null) return null
            return AlertCard(title, body.orEmpty(), kind)
        }

        fun advice(kind: String): Int? = when (kind) {
            "gnx.alert.raid" -> R.string.alert_advice_raid
            "gnx.alert.smart" -> R.string.alert_advice_smart
            "gnx.alert.space" -> R.string.alert_advice_space
            "gnx.alert.backup" -> R.string.alert_advice_backup
            "gnx.alert.drive_stale" -> R.string.alert_advice_drive_stale
            "gnx.alert.drive_readonly" -> R.string.alert_advice_drive_readonly
            "gnx.alert.load" -> R.string.alert_advice_load
            "gnx.alert.memory" -> R.string.alert_advice_memory
            else -> null
        }
    }
}
