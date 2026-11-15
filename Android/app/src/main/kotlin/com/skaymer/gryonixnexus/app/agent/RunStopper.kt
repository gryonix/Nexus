package com.skaymer.gryonixnexus.app.agent

import com.skaymer.gryonixnexus.agentcontrol.AgentJob
import com.skaymer.gryonixnexus.agentcontrol.AgentJobOperations
import com.skaymer.gryonixnexus.app.notify.StopMiss
import com.skaymer.gryonixnexus.app.notify.StopRefusalText
import com.skaymer.gryonixnexus.servercontrol.Deployment

/** Stops the agent runs a notification's action started */
class RunStopper(private val operations: suspend (Deployment) -> AgentJobOperations) {
    /** Cancels running jobs begun near [startedAtMillis]; rethrows a refusal */
    suspend fun stop(deployment: Deployment, startedAtMillis: Long) {
        val ops = operations(deployment)
        var refusal: Throwable? = null
        val running = targets(ops.jobs(runningOnly = true), startedAtMillis)
        if (running.isEmpty()) throw StopMiss(StopRefusalText.Reason.NothingRunning)
        for (job in running) {
            runCatching { ops.cancel(job.id) }.onFailure { refusal = it }
        }
        refusal?.let { throw it }
    }

    companion object {
        const val LEAD_MILLIS = 5_000L

        /** Running jobs that started within the lead before the run */
        fun targets(running: List<AgentJob>, startedAtMillis: Long): List<AgentJob> =
            running.filter { it.isRunning && it.started.toEpochMilli() >= startedAtMillis - LEAD_MILLIS }
    }
}
