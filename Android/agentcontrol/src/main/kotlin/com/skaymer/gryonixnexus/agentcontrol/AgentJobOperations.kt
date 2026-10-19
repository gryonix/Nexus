package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import gryonixnexusd.v1.Job
import gryonixnexusd.v1.JobKind
import gryonixnexusd.v1.JobOutcome
import gryonixnexusd.v1.JobPhase
import java.time.Instant

data class AgentJob(
    val id: String,
    val kind: AgentJobKind,
    val subject: String,
    val started: Instant,
    /** Null while the run is still going */
    val finished: Instant?,
    val outcome: AgentJobOutcome,
    val failure: String,
    val events: Long,
    /** The install plan this run is part of */
    val partOf: String = "",
    /** Set on an install plan's own job */
    val planPurpose: AgentPlanPurpose = AgentPlanPurpose.ADD,
) {
    val isRunning: Boolean get() = outcome == AgentJobOutcome.RUNNING
}

enum class AgentJobKind {
    INSTALL, UPDATE, BACKUP, RESTORE, UNINSTALL,

    /** An install plan running every service again */
    REPAIR, REINSTALL,

    SERVICE_CONTROL, CONTAINER_UPDATE, CONTAINER_BACKUP, CONTAINER_REMOVAL, CONTAINER_CONTROL,

    /** Fetching a model onto the local engine */
    MODEL_PULL,

    SECURITY_CONTROL,

    /** ApplyAgentUpdate's own journal */
    AGENT_UPDATE,

    /** Sending or unpacking a service that moves between machines */
    MOVE,

    /** A kind this build has no name for */
    UNKNOWN,
}

enum class AgentJobOutcome {
    RUNNING, SUCCEEDED, FAILED,

    CANCELLED,

    ABANDONED,
    UNKNOWN,
}

/** Reading and re-attaching to the host's long runs */
class AgentJobOperations(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
) {
    /** What this host is doing, or has just done */
    suspend fun jobs(runningOnly: Boolean = false): List<AgentJob> {
        val call = suspend { client.listJobs(runningOnly = runningOnly) }
        val jobs = gate?.withSlot { call() } ?: call()
        return jobs.map { it.toAgentJob() }
    }

    /** Asks the host to stop one run */
    suspend fun cancel(jobID: String) {
        val call = suspend { client.cancelJob(jobID) }
        gate?.withSlot { call() } ?: call()
    }

    suspend fun watch(jobID: String, from: Long = 0L, onChunk: (String) -> Unit) {
        client.watchJob(jobID, from).collect { event ->
            if (event.phase != JobPhase.JOB_PHASE_PROGRESS &&
                event.phase != JobPhase.JOB_PHASE_STARTED
            ) {
                return@collect
            }
            if (event.text.isEmpty()) return@collect
            onChunk(if (event.text.endsWith("\n")) event.text else event.text + "\n")
        }
    }
}

private fun Job.toAgentJob(): AgentJob = AgentJob(
    id = job_id,
    kind = when (kind) {
        JobKind.JOB_KIND_INSTALL -> AgentJobKind.INSTALL
        JobKind.JOB_KIND_UPDATE -> AgentJobKind.UPDATE
        JobKind.JOB_KIND_BACKUP -> AgentJobKind.BACKUP
        JobKind.JOB_KIND_RESTORE -> AgentJobKind.RESTORE
        JobKind.JOB_KIND_UNINSTALL -> AgentJobKind.UNINSTALL
        JobKind.JOB_KIND_SERVICE_CONTROL -> AgentJobKind.SERVICE_CONTROL
        JobKind.JOB_KIND_CONTAINER_UPDATE -> AgentJobKind.CONTAINER_UPDATE
        JobKind.JOB_KIND_CONTAINER_BACKUP -> AgentJobKind.CONTAINER_BACKUP
        JobKind.JOB_KIND_CONTAINER_REMOVAL -> AgentJobKind.CONTAINER_REMOVAL
        JobKind.JOB_KIND_CONTAINER_CONTROL -> AgentJobKind.CONTAINER_CONTROL
        JobKind.JOB_KIND_MODEL_PULL -> AgentJobKind.MODEL_PULL
        JobKind.JOB_KIND_SECURITY_CONTROL -> AgentJobKind.SECURITY_CONTROL
        JobKind.JOB_KIND_AGENT_UPDATE -> AgentJobKind.AGENT_UPDATE
        JobKind.JOB_KIND_MOVE -> AgentJobKind.MOVE
        JobKind.JOB_KIND_REPAIR -> AgentJobKind.REPAIR
        JobKind.JOB_KIND_REINSTALL -> AgentJobKind.REINSTALL
        JobKind.JOB_KIND_UNSPECIFIED -> AgentJobKind.UNKNOWN
    },
    subject = subject,
    started = Instant.ofEpochSecond(started_unix),
    finished = if (finished_unix > 0L) Instant.ofEpochSecond(finished_unix) else null,
    outcome = when (outcome) {
        JobOutcome.JOB_OUTCOME_RUNNING -> AgentJobOutcome.RUNNING
        JobOutcome.JOB_OUTCOME_SUCCEEDED -> AgentJobOutcome.SUCCEEDED
        JobOutcome.JOB_OUTCOME_FAILED -> AgentJobOutcome.FAILED
        JobOutcome.JOB_OUTCOME_ABANDONED -> AgentJobOutcome.ABANDONED
        JobOutcome.JOB_OUTCOME_CANCELLED -> AgentJobOutcome.CANCELLED
        JobOutcome.JOB_OUTCOME_UNSPECIFIED -> AgentJobOutcome.UNKNOWN
    },
    failure = failure,
    events = events,
    partOf = part_of,
    planPurpose = AgentPlanPurpose.of(plan_purpose),
)
