package com.skaymer.gryonixnexus.catalog.storage

import com.skaymer.gryonixnexus.catalog.Apt
/** Moves live databases and caches onto a fast disk */
data class FastStorageMove(val target: FastStoragePlan.Target, val projects: List<Project>) {
    /** One compose project and its hot directories */
    data class Project(val directory: String, val hotPaths: List<String>)

    val root: String get() = FastStoragePlan(target, emptyList()).root

    fun script(): String {
        val lines = mutableListOf("#!/bin/bash", "set -euo pipefail", "FAST=${FastStoragePlan.quoted(root)}")
        lines += when (val t = target) {
            is FastStoragePlan.Target.Device -> FastStoragePlan.formatLines(t.path)
            is FastStoragePlan.Target.Folder -> listOf("install -d \"\$FAST\"")
        }
        lines += RSYNC_LINES + moveFunctions()
        for (project in projects) {
            val dirs = project.hotPaths.joinToString(" ") { FastStoragePlan.quoted(it) }
            lines += "move_project ${FastStoragePlan.quoted(project.directory)} $dirs || FAILED=1"
        }
        lines += listOf("[ \"\${FAILED:-0}\" = 0 ] || exit 4", "echo $DONE_MARKER")
        return lines.joinToString("\n") + "\n"
    }

    companion object {
        const val DONE_MARKER = "GRYONIXNEXUS_FAST_MOVE_DONE"
        const val COMPOSE_MARKER = "### "
        private const val MOUNTED_MARKER = "GRYONIXNEXUS_FAST_MOUNTED"
        private const val BOUND_MARKER = "GRYONIXNEXUS_FAST_BOUND"

        /** Folders already living on the fast disk */
        fun bound(probe: String): Set<String> =
            probe.split("\n").filter { it.startsWith("$BOUND_MARKER ") }.map { it.removePrefix("$BOUND_MARKER ") }.toSet()

        /** Prints each compose file after a header line */
        val PROBE_COMMAND =
            "for f in \$(ls -d /opt/*/docker-compose.y*ml /opt/*/compose.y*ml /srv/*/docker-compose.y*ml 2>/dev/null); " +
                "do echo \"$COMPOSE_MARKER\$f\"; cat \"\$f\"; echo; done; " +
                "mountpoint -q ${FastStoragePlan.MOUNT_POINT} && echo \"$MOUNTED_MARKER\" || true; " +
                "awk '\$3 == \"none\" && \$1 ~ /gryonixnexus-fast\\/binds/ {print \"$BOUND_MARKER \" \$2}' /etc/fstab"

        /** Projects with hot directories, read from the probe */
        fun projects(probe: String): List<Project> {
            val result = mutableListOf<Project>()
            var file: String? = null
            val body = StringBuilder()
            fun flush() {
                val current = file ?: return
                val hot = FastStoragePlan.hotPathsInText(body.toString())
                if (hot.isNotEmpty()) result += Project(current.substringBeforeLast('/'), hot)
            }
            for (line in probe.split("\n")) {
                if (line.startsWith(COMPOSE_MARKER)) {
                    flush()
                    file = line.removePrefix(COMPOSE_MARKER)
                    body.clear()
                } else {
                    body.append(line).append('\n')
                }
            }
            flush()
            return result
        }

        fun isMounted(probe: String): Boolean = probe.split("\n").any { it == MOUNTED_MARKER }

        internal val RSYNC_LINES = listOf(
            "if ! command -v rsync >/dev/null 2>&1; then",
            "  export DEBIAN_FRONTEND=noninteractive",
            "  ${Apt.QUIET} install -y -qq rsync >/dev/null",
            "fi",
        )

        /** Stop, copy, keep the old copy aside, bind, start again */
        private fun moveFunctions() = listOf(
            "move_dir() {",
            "  local target=\"\$1\" source=\"\$FAST/binds\$1\" old=\"\$1.before-cache\"",
            "  if mountpoint -q \"\$target\"; then echo \"\$target is already on the fast disk\"; return 0; fi",
            "  if [ ! -d \"\$target\" ]; then echo \"\$target does not exist, skipped\"; return 0; fi",
            "  echo \"Moving \$target\"",
            "  install -d \"\$source\" || return 1",
            "  rsync -aHAX --delete \"\$target/\" \"\$source/\" || return 1",
            "  if [ -e \"\$old\" ]; then old=\"\$old.\$(date +%s)\"; fi",
            "  mv \"\$target\" \"\$old\" || return 1",
            "  install -d \"\$target\" || return 1",
            "  " + FastStoragePlan.bindLine("\$source", "\$target") + " || return 1",
            "  mount \"\$target\" || return 1",
            "}",
            "move_project() {",
            "  local project=\"\$1\" rc=0 todo=0",
            "  shift",
            "  for dir in \"\$@\"; do mountpoint -q \"\$dir\" || todo=1; done",
            "  if [ \"\$todo\" = 0 ]; then echo \"\$project is already on the fast disk\"; return 0; fi",
            "  (cd \"\$project\" && docker compose stop) || return 1",
            "  for dir in \"\$@\"; do move_dir \"\$dir\" || rc=1; done",
            "  (cd \"\$project\" && docker compose start) || rc=1",
            "  return \$rc",
            "}",
        )
    }
}
