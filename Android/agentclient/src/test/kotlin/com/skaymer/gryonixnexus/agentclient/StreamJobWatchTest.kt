package com.skaymer.gryonixnexus.agentclient

import gryonixnexusd.v1.Job
import gryonixnexusd.v1.JobList
import gryonixnexusd.v1.JobOutcome
import gryonixnexusd.v1.UpdateEvent
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class StreamJobWatchTest {
    private class Silent(private val outcome: JobOutcome) : AgentTransport {
        var listed = 0

        override suspend fun unary(path: String, request: ByteArray): ByteArray {
            listed++
            return JobList(jobs = listOf(Job(job_id = "6ac-1", outcome = outcome))).encode()
        }

        override fun serverStream(path: String, request: ByteArray): Flow<ByteArray> = flow {
            emit(UpdateEvent(job_id = "6ac-1").encode())
            awaitCancellation()
        }
    }

    @Test
    fun `a stream whose job ended on the server fails as a lost connection`() = runTest {
        val transport = Silent(JobOutcome.JOB_OUTCOME_SUCCEEDED)
        val failure = assertFailsWith<AgentError.Transport> { AgentClient(transport).runUpdate("immich").toList() }
        assertTrue(failure.detail.contains("6ac-1"), failure.detail)
        assertEquals(2, transport.listed, "it waits one more interval before giving up on the stream")
    }

    @Test
    fun `the job id is read from any job event`() {
        assertEquals("6ac-1", StreamJobWatch.jobIdOf(UpdateEvent(job_id = "6ac-1")))
        assertEquals("", StreamJobWatch.jobIdOf("not an event"))
    }
}
