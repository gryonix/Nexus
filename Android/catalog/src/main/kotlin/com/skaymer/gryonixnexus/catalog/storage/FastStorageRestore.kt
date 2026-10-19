package com.skaymer.gryonixnexus.catalog.storage

/** Returns moved folders or deletes their old copies */
object FastStorageRestore {
    const val DONE_MARKER = "GRYONIXNEXUS_FAST_RESTORE_DONE"
    const val CLEANUP_DONE_MARKER = "GRYONIXNEXUS_FAST_CLEANUP_DONE"

    /** Stop, copy the current data back, unbind, start again */
    fun script(projects: List<FastStorageMove.Project>): String {
        val lines = mutableListOf("#!/bin/bash", "set -euo pipefail")
        lines += FastStorageMove.RSYNC_LINES + functions()
        for (project in projects) {
            val dirs = project.hotPaths.joinToString(" ") { FastStoragePlan.quoted(it) }
            lines += "restore_project ${FastStoragePlan.quoted(project.directory)} $dirs || FAILED=1"
        }
        lines += listOf("[ \"\${FAILED:-0}\" = 0 ] || exit 4", "echo $DONE_MARKER")
        return lines.joinToString("\n") + "\n"
    }

    /** Deletes the copies a move left beside each folder */
    fun cleanupScript(paths: List<String>): String {
        val lines = mutableListOf("#!/bin/bash", "set -euo pipefail")
        for (path in paths) {
            val old = FastStoragePlan.quoted("$path.before-cache")
            lines += "for old in $old $old.*; do [ -d \"\$old\" ] || continue; rm -rf -- \"\$old\"; echo \"removed \$old\"; done"
        }
        lines += "echo $CLEANUP_DONE_MARKER"
        return lines.joinToString("\n") + "\n"
    }

    private fun functions() = listOf(
        "bound_source() {",
        "  awk -v t=\"\$1\" '\$2 == t && \$3 == \"none\" {print \$1; exit}' /etc/fstab",
        "}",
        "restore_dir() {",
        "  local target=\"\$1\" source",
        "  source=\"\$(bound_source \"\$target\")\"",
        "  if [ -z \"\$source\" ]; then echo \"\$target is not on the fast disk\"; return 0; fi",
        "  echo \"Bringing back \$target\"",
        "  if mountpoint -q \"\$target\"; then umount \"\$target\" || return 1; fi",
        "  rsync -aHAX --delete \"\$source/\" \"\$target/\" || return 1",
        "  awk -v t=\"\$target\" '!(\$2 == t && \$3 == \"none\")' /etc/fstab > /etc/fstab.gryonixnexus || return 1",
        "  cat /etc/fstab.gryonixnexus > /etc/fstab && rm -f /etc/fstab.gryonixnexus || return 1",
        "}",
        "restore_project() {",
        "  local project=\"\$1\" rc=0 todo=0",
        "  shift",
        "  for dir in \"\$@\"; do [ -n \"\$(bound_source \"\$dir\")\" ] && todo=1; done",
        "  if [ \"\$todo\" = 0 ]; then echo \"\$project is on the system disk\"; return 0; fi",
        "  (cd \"\$project\" && docker compose stop) || return 1",
        "  for dir in \"\$@\"; do restore_dir \"\$dir\" || rc=1; done",
        "  (cd \"\$project\" && docker compose start) || rc=1",
        "  return \$rc",
        "}",
    )
}
