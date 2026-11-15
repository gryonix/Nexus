package com.skaymer.gryonixnexus.app.agent

import com.skaymer.gryonixnexus.agentcontrol.AgentJob
import com.skaymer.gryonixnexus.agentcontrol.AgentJobKind
import com.skaymer.gryonixnexus.agentcontrol.AgentJobOutcome
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

/** A tapped alert finds its run and opens its page */
class RunOpeningTests {
    private fun job(id: String, running: Boolean) = AgentJob(
        id = id,
        kind = AgentJobKind.UPDATE,
        subject = "nextcloud",
        started = Instant.ofEpochSecond(1_000),
        finished = if (running) null else Instant.ofEpochSecond(1_100),
        outcome = if (running) AgentJobOutcome.RUNNING else AgentJobOutcome.FAILED,
        failure = if (running) "" else "pull failed",
        events = 3,
    )

    @Test
    fun `the run is found by its id whether it still runs or has ended`() {
        val listed = listOf(job("job-1", running = true), job("job-2", running = false))
        assertEquals("job-2", RunningJobs.named("job-2", listed)?.id)
        assertEquals("job-1", RunningJobs.named("job-1", listed)?.id)
        assertNull(RunningJobs.named("job-3", listed), "a run the server forgot")
        assertNull(RunningJobs.named("job-1", emptyList()))
    }

    @Test
    fun `the asked run stays asked until its page is closed`() = runTest {
        val jobs = RunningJobs(
            scope = CoroutineScope(StandardTestDispatcher(testScheduler)),
            deployments = { emptyList() },
            operations = { error("no server in this test") },
            runners = { error("no server in this test") },
        )
        assertNull(jobs.opened.value)
        jobs.open("job-1")
        assertEquals("job-1", jobs.opened.value)
        jobs.close()
        assertNull(jobs.opened.value)
    }
}
