package com.skaymer.gryonixnexus.app.session

import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import kotlin.time.Duration.Companion.seconds

class ConnectionCheck(private val sessions: ServerSessions) {
    /** Servers currently answering at their FALLBACK address */
    val onFallback get() = sessions.onFallback

    sealed interface Result {
        data class Reachable(val identity: String, val system: String) : Result
        data class Refused(val reason: String) : Result
    }

    suspend fun check(deployment: Deployment): Result = try {
        val runner = sessions.runner(deployment)
        val result = runner.run("id -un; uname -sr", SSHHostID.VPS, 15.seconds)
        val lines = result.stdout.trim().lines()
        if (result.exitCode == 0 && lines.size >= 2) {
            Result.Reachable(identity = lines[0].trim(), system = lines[1].trim())
        } else {
            Result.Refused(result.stderr.trim().ifEmpty { "exit ${result.exitCode}" })
        }
    } catch (failure: Exception) {
        Result.Refused(failure.message ?: failure::class.simpleName.orEmpty())
    }
}
