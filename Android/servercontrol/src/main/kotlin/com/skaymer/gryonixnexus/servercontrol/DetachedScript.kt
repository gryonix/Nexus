package com.skaymer.gryonixnexus.servercontrol

import java.util.Base64
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/** A script run detached, read back across reconnects */
object DetachedScript {
    /** Runs the script from a temporary file, removed afterwards */
    fun command(script: String, elevated: Boolean): String {
        val encoded = Base64.getEncoder().encodeToString(script.toByteArray())
        val elevate = if (elevated) "sudo -n " else ""
        return "f=\"\$(mktemp)\" && printf '%s' '$encoded' | base64 -d > \"\$f\" && " +
            "( ${elevate}bash \"\$f\"; rc=\$?; rm -f \"\$f\"; exit \$rc )"
    }

    /** Everything the script printed, and how it ended */
    suspend fun output(
        script: String,
        elevated: Boolean,
        subject: String,
        runner: SSHCommandRunner,
        host: SSHHostID,
        quickTimeout: Duration = 30.seconds,
        runTimeout: Duration = 900.seconds,
        retryDelay: Duration = 3.seconds,
        now: Long = System.currentTimeMillis() / 1000,
    ): DetachedJobs.Followed {
        val id = DetachedJobs.jobID(DetachedJobs.Kind.MEASURE, subject, now)
        runner.run(DetachedJobs.startCommand(command(script, elevated), id), host, quickTimeout)
        return DetachedJobs.follow(runner, host, id, runTimeout, retryDelay = retryDelay) {}
    }
}
