package com.skaymer.gryonixnexus.agentclient

import gryonixnexusd.v1.AgentUpdateEvent
import gryonixnexusd.v1.BackupEvent
import gryonixnexusd.v1.ContainerBackupEvent
import gryonixnexusd.v1.ContainerOperationEvent
import gryonixnexusd.v1.ContainerRemovalEvent
import gryonixnexusd.v1.ContainerUpdateEvent
import gryonixnexusd.v1.InstallServiceEvent
import gryonixnexusd.v1.JobOutcome
import gryonixnexusd.v1.ModelPullEvent
import gryonixnexusd.v1.MoveEvent
import gryonixnexusd.v1.RestoreEvent
import gryonixnexusd.v1.SecurityOperationEvent
import gryonixnexusd.v1.ServiceOperationEvent
import gryonixnexusd.v1.UninstallEvent
import gryonixnexusd.v1.UpdateEvent
import kotlinx.coroutines.delay

/** Ends a stream whose agent job finished without telling it */
internal object StreamJobWatch {
    const val INTERVAL_MILLIS = 20_000L

    /** The agent job an event belongs to, or empty */
    fun jobIdOf(message: Any): String = when (message) {
        is AgentUpdateEvent -> message.job_id
        is BackupEvent -> message.job_id
        is ContainerBackupEvent -> message.job_id
        is ContainerOperationEvent -> message.job_id
        is ContainerRemovalEvent -> message.job_id
        is ContainerUpdateEvent -> message.job_id
        is InstallServiceEvent -> message.job_id
        is ModelPullEvent -> message.job_id
        is MoveEvent -> message.job_id
        is RestoreEvent -> message.job_id
        is SecurityOperationEvent -> message.job_id
        is ServiceOperationEvent -> message.job_id
        is UninstallEvent -> message.job_id
        is UpdateEvent -> message.job_id
        else -> ""
    }

    /** Waits until the job stays ended for a full interval */
    suspend fun awaitServerEnd(jobId: String, outcome: suspend (String) -> JobOutcome?,
                               interval: Long = INTERVAL_MILLIS) {
        var endSeen = false
        while (true) {
            delay(interval)
            val now = runCatching { outcome(jobId) }.getOrNull() ?: continue
            val ended = now != JobOutcome.JOB_OUTCOME_RUNNING && now != JobOutcome.JOB_OUTCOME_UNSPECIFIED
            if (ended && endSeen) return
            endSeen = ended
        }
    }
}
