package com.skaymer.gryonixnexus.catalog.storage

/** The long disk task a server runs in the background */
data class DiskJob(
    /** The array change it carries out */
    val action: String,
    /** The array it works on */
    val target: String,
    /** Seconds since 1970, when it started */
    val started: Long?,
    val outcome: Outcome,
    /** The newest lines of its log */
    val lastLines: List<String>,
) {
    enum class Outcome { RUNNING, DONE, FAILED }

    /** Running, or started within the last three days */
    fun isRecent(nowSeconds: Long = System.currentTimeMillis() / 1000): Boolean {
        if (outcome == Outcome.RUNNING || started == null) return true
        return nowSeconds - started < 3 * 24 * 3600
    }

    companion object {
        const val UNIT = "gryonixnexus-disk-job"
        const val LOG = "/var/log/gryonixnexus-disk-job.log"
        const val FILE = "/var/lib/gryonixnexus-disk-job.sh"
        private const val START_MARKER = "GRYONIXNEXUS_DISK_JOB_START"
        private const val DONE_MARKER = "GRYONIXNEXUS_DISK_JOB_DONE"
        private const val FAILED_MARKER = "GRYONIXNEXUS_DISK_JOB_FAILED"

        /** Probe line: unit state, first log line, last log lines */
        val PROBE_LINE = "echo \"diskjob=\$(systemctl is-active $UNIT 2>/dev/null)|" +
            "\$(head -n 1 $LOG 2>/dev/null)|\$(tail -n 3 $LOG 2>/dev/null | tr '\\n' '|')\""

        fun parse(field: String): DiskJob? {
            val parts = field.split("|").map { it.trim() }
            if (parts.size < 2) return null
            val start = parts[1].split(" ").filter { it.isNotEmpty() }
            if (start.size < 3 || start[0] != START_MARKER) return null
            val tail = parts.drop(2).filter { it.isNotEmpty() }
            val last = tail.lastOrNull().orEmpty()
            val outcome = when {
                last.startsWith(DONE_MARKER) -> Outcome.DONE
                last.startsWith(FAILED_MARKER) -> Outcome.FAILED
                parts[0] == "active" || parts[0] == "activating" -> Outcome.RUNNING
                else -> Outcome.FAILED
            }
            return DiskJob(
                action = start[1], target = start[2], started = start.getOrNull(3)?.toDoubleOrNull()?.toLong(),
                outcome = outcome,
                lastLines = tail.filter { !it.startsWith(DONE_MARKER) && !it.startsWith(FAILED_MARKER) },
            )
        }

        /** Refuses while another disk job runs */
        val BUSY_GUARD = listOf(
            "if systemctl is-active -q $UNIT; then",
            "  echo \"Another disk job is still running. Wait until it ends.\"",
            "  exit 3",
            "fi",
        )

        /** Writes the body to a file and starts its unit */
        fun launchLines(action: String, target: String, variables: List<String>, body: List<String>): List<String> =
            listOf(
                "cat > $FILE <<'GNX_JOB'",
                "#!/bin/bash",
                "set -eEuo pipefail",
                "exec >> $LOG 2>&1",
                "trap 'echo \"$FAILED_MARKER \$(date +%s)\"' ERR",
                "echo \"$START_MARKER $action $target \$(date +%s)\"",
            ) + variables + body + listOf(
                "echo \"$DONE_MARKER \$(date +%s)\"",
                "GNX_JOB",
                ": > $LOG",
                "chmod 644 $LOG",
                "systemctl reset-failed $UNIT >/dev/null 2>&1 || true",
                "systemd-run --quiet --collect --unit=$UNIT /bin/bash $FILE",
            )
    }
}
