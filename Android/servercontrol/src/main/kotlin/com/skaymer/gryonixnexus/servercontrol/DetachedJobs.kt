package com.skaymer.gryonixnexus.servercontrol

import kotlin.coroutines.cancellation.CancellationException
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.delay

object DetachedJobs {
    /** A job's output and its exit code, if it ended */
    data class Followed(val output: String, val exitCode: Int?)

    /** Follows a job's log, re-attaching after drops */
    suspend fun follow(
        runner: SSHCommandRunner,
        host: SSHHostID,
        id: String,
        timeout: Duration,
        reattaches: Int = 5,
        retryDelay: Duration = 3.seconds,
        onChunk: (String) -> Unit,
    ): Followed {
        val accumulated = StringBuilder()
        var exit: Int? = null
        var consumed = 0
        var attempt = 0
        while (true) {
            val before = consumed
            try {
                runner.stream(followCommand(id, consumed + 1), host, timeout).collect { chunk ->
                    consumed += chunk.text.count { it == '\n' }
                    for (piece in chunk.text.split("\n")) {
                        if (piece.startsWith(EXIT_MARKER)) {
                            exit = piece.removePrefix(EXIT_MARKER).trim().toIntOrNull() ?: -1
                            continue
                        }
                        if (piece.isEmpty()) continue
                        accumulated.append(piece).append("\n")
                        onChunk(piece + "\n")
                    }
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Throwable) {
                if (exit == null && attempt >= reattaches) throw error
            }
            if (exit != null) break
            if (consumed > before) attempt = 0
            if (attempt >= reattaches) break
            attempt++
            delay(retryDelay)
        }
        return Followed(accumulated.toString(), exit)
    }

    enum class Kind(val raw: String) {
        UPDATE("update"), BACKUP("backup"), RESTORE("restore"),
        UNINSTALL("uninstall"), CONTROL("control");

        companion object {
            fun from(raw: String): Kind? = entries.firstOrNull { it.raw == raw }
        }
    }

    data class Job(
        val id: String,
        val kind: Kind,
        val subject: String,
        val startedUnix: Long,
        val exitCode: Int?,
    ) {
        val isRunning: Boolean get() = exitCode == null
    }

    const val DIRECTORY = ".gryonixnexus/jobs"

    /** The line the launcher appends when the work is over */
    const val EXIT_MARKER = "GRYONIXNEXUS_JOB_EXIT:"

    fun jobID(kind: Kind, subject: String, at: Long): String {
        val safe = subject.map { if (it.isLetterOrDigit() || it == '-') it else '-' }.joinToString("")
        return "${kind.raw}-$safe-$at"
    }

    fun startCommand(command: String, jobID: String): String {
        val log = ShellQuoting.singleQuoted("$DIRECTORY/$jobID.log")
        val payload = "$command >> $log 2>&1; echo \"$EXIT_MARKER${'$'}?\" >> $log"
        return reservation(jobID) + ": > $log || exit 1; " +
            "command -v setsid >/dev/null 2>&1 && DETACH=setsid || DETACH=; " +
            "${'$'}DETACH sh -c ${ShellQuoting.singleQuoted(payload)} </dev/null >/dev/null 2>&1 & " +
            "echo ${ShellQuoting.singleQuoted(jobID)}"
    }

    /** Launches a job reading its secret from stdin */
    fun startCommandWithSecret(command: String, jobID: String): String {
        val log = ShellQuoting.singleQuoted("$DIRECTORY/$jobID.log")
        val pass = ShellQuoting.singleQuoted("$DIRECTORY/$jobID.pass")
        val payload = "{ cat $pass; rm -f $pass; } | $command >> $log 2>&1; " +
            "echo \"$EXIT_MARKER${'$'}?\" >> $log"
        return reservation(jobID) + ": > $log " +
            "&& cat > $pass || exit 1; " +
            "command -v setsid >/dev/null 2>&1 && DETACH=setsid || DETACH=; " +
            "${'$'}DETACH sh -c ${ShellQuoting.singleQuoted(payload)} </dev/null >/dev/null 2>&1 & " +
            "echo ${ShellQuoting.singleQuoted(jobID)}"
    }

    private fun reservation(jobID: String): String {
        val subject = jobID.split("-").drop(1).dropLast(1).joinToString("-")
        val lock = ShellQuoting.singleQuoted("$DIRECTORY/$subject.lock")
        return "umask 077; mkdir -p ${ShellQuoting.singleQuoted(DIRECTORY)} || exit 1; " +
            "exec 9> $lock; flock -n 9 || { echo 'An operation is already running for this service. Wait for it to finish.' >&2; exit 75; }; "
    }

    fun followCommand(jobID: String, fromLine: Int): String {
        val log = ShellQuoting.singleQuoted("$DIRECTORY/$jobID.log")
        return """
            n=$fromLine
            while :; do
              tot=${'$'}(wc -l < $log 2>/dev/null || echo 0)
              if [ "${'$'}tot" -ge "${'$'}n" ]; then sed -n "${'$'}{n},${'$'}{tot}p" $log; n=${'$'}((tot + 1)); fi
              if [ "${'$'}tot" -ge 1 ] && sed -n "${'$'}{tot}p" $log | grep -q "^$EXIT_MARKER"; then exit 0; fi
              sleep 1
            done
        """.trimIndent()
    }

    fun listCommand(): String {
        val dir = ShellQuoting.singleQuoted(DIRECTORY)
        return """
            cd $dir 2>/dev/null || exit 0
            for f in *.log; do
              [ -e "${'$'}f" ] || continue
              id=${'$'}{f%.log}
              last=${'$'}(tail -n 1 "${'$'}f" 2>/dev/null)
              case "${'$'}last" in
                $EXIT_MARKER*) code=${'$'}{last#$EXIT_MARKER} ;;
                *) code=- ;;
              esac
              echo "${'$'}id ${'$'}code"
            done
        """.trimIndent()
    }

    /** Parses what [listCommand] printed */
    fun parseList(output: String): List<Job> = output.lineSequence()
        .mapNotNull { line ->
            val parts = line.trim().split(" ")
            if (parts.size != 2) return@mapNotNull null
            val id = parts[0]
            val fields = id.split("-")
            if (fields.size < 3) return@mapNotNull null
            val kind = Kind.from(fields[0]) ?: return@mapNotNull null
            val started = fields.last().toLongOrNull() ?: return@mapNotNull null
            val subject = fields.subList(1, fields.size - 1).joinToString("-")
            val code = if (parts[1] == "-") null else (parts[1].toIntOrNull() ?: -1)
            Job(id = id, kind = kind, subject = subject, startedUnix = started, exitCode = code)
        }
        .sortedByDescending { it.startedUnix }
        .toList()
}
