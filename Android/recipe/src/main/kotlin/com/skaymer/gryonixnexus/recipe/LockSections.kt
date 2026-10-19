package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.SH

internal object LockSections {
    /** Where per-service lock files live */
    const val DIRECTORY = "/var/lib/gryonixnexus/locks"

    const val BUSY_EXIT_CODE = "75"

    val helper = """
    GD_LOCK_BUSY=$BUSY_EXIT_CODE

    gd_with_lock() {
      local id="${SH}1"
      shift
      install -d -m 700 '$DIRECTORY'
      local fd
      exec {fd}>"$DIRECTORY/${SH}id.lock"
      if ! flock -n "${SH}fd"; then
        echo "${SH}id: another backup or update for this service is already running, skipping" >&2
        return "${SH}GD_LOCK_BUSY"
      fi
      "${SH}@"
    }
    """.trimIndent()
}
