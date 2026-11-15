package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.servercontrol.HostNameRules

/** When an edited setting waits in the bar */
object PendingRules {
    /** A valid, changed value waits unless work runs */
    fun <T> waits(draft: T?, saved: T?, valid: Boolean = true, busy: Boolean = false): Boolean =
        draft != null && draft != saved && valid && !busy

    fun hostName(draft: String, saved: String): Boolean = waits(draft, saved, valid = HostNameRules.isValid(draft))

    /** A typed passphrase waits even with an unchanged schedule */
    fun backupSchedule(canSave: Boolean, changed: Boolean, typedPassphrase: String): Boolean =
        canSave && (changed || typedPassphrase.isNotEmpty())
}
