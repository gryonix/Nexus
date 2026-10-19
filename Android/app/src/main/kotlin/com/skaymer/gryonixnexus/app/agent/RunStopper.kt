package com.skaymer.gryonixnexus.app.agent

import com.skaymer.gryonixnexus.agentcontrol.AgentJob
import com.skaymer.gryonixnexus.agentcontrol.AgentJobOperations
import com.skaymer.gryonixnexus.servercontrol.Deployment

/** Stops the agent runs a notification's action started */
class RunStopper(private val operations: suspend (Deployment) -> AgentJobOperations) {
    /** Cancels every running job begun shortly before [startedAtMillis] */
    suspend fun stop(deployment: Deployment, startedAtMillis: Long) {
        val ops = operations(deployment)
        for (job in targets(ops.jobs(runningOnly = true), startedAtMillis)) {
            runCatching { ops.cancel(job.id) }
        }
    }

    companion object {
        const val LEAD_MILLIS = 5_000L

        /** Running jobs that started within the lead before the run */
        fun targets(running: List<AgentJob>, startedAtMillis: Long): List<AgentJob> =
            running.filter { it.isRunning && it.started.toEpochMilli() >= startedAtMillis - LEAD_MILLIS }
    }
}
