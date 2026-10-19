package com.skaymer.gryonixnexus.app.agent

import com.skaymer.gryonixnexus.agentcontrol.AgentJob
import com.skaymer.gryonixnexus.agentcontrol.AgentJobKind
import com.skaymer.gryonixnexus.agentcontrol.AgentJobOutcome
import java.time.Instant
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals

class RunStopperTest {
    private fun job(id: String, startedMillis: Long, outcome: AgentJobOutcome = AgentJobOutcome.RUNNING) =
        AgentJob(id, AgentJobKind.UPDATE, "caddy", Instant.ofEpochMilli(startedMillis), null, outcome, "", 0)

    @Test
    fun onlyRunningJobsFromJustBeforeTheRunAreStopped() {
        val jobs = listOf(
            job("old", 1_000),
            job("lead", 96_000),
            job("fresh", 120_000),
            job("done", 120_000, AgentJobOutcome.SUCCEEDED),
        )
        assertEquals(listOf("lead", "fresh"), RunStopper.targets(jobs, 100_000).map { it.id })
    }
}
