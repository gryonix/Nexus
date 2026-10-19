package com.skaymer.gryonixnexus.servercontrol

object CommandMarkers {
    object Restore {
        const val DONE = "GRYONIXNEXUS_RESTORE_DONE"
    }

    object Uninstall {
        const val DONE = "GRYONIXNEXUS_UNINSTALL_DONE"
    }

    object Dkim {
        const val DONE = "GRYONIXNEXUS_DKIM_DONE"
    }

    object Mailbox {
        const val DONE = "GRYONIXNEXUS_MAILBOX_DONE"
    }

    object Backups {
        const val CONTROL_DONE = "GRYONIXNEXUS_BACKUP_CTL_DONE"

        /** Announces the finished archive */
        const val BACKUP_DONE = "GRYONIXNEXUS_BACKUP_DONE"
        const val ESTIMATE = "GRYONIXNEXUS_BACKUP_ESTIMATE"
    }

    object Update {
        const val DONE = "GRYONIXNEXUS_UPDATE_CTL_DONE"
        const val AVAILABLE = "GRYONIXNEXUS_UPDATE_AVAILABLE"
        const val CURRENT = "GRYONIXNEXUS_UPDATE_CURRENT"
        const val UNKNOWN = "GRYONIXNEXUS_UPDATE_UNKNOWN"
        const val UPDATED = "GRYONIXNEXUS_UPDATE_DONE"
        const val ROLLED_BACK = "GRYONIXNEXUS_UPDATE_ROLLED_BACK"
        const val FAILED = "GRYONIXNEXUS_UPDATE_FAILED"
    }
}
