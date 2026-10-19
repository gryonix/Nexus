package com.skaymer.gryonixnexus.app.metrics

import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.ExecChunk
import com.skaymer.gryonixnexus.servercontrol.ExecResult
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.SleepProvider
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

/** What the history screen does between asking and drawing */
class HistoryViewModelTests {
    private fun server(id: String = "H-1") = Deployment(
        id = id,
        name = "history",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.30", user = "root"),
    )

    private val csv = """
        1756300000,12.5,536870912,1073741824,268435456,1073741824,1000,500,10,20,0.42,42.5
        1756300060,15.0,566870912,1073741824,268435456,1073741824,1100,600,11,21,0.44,42.5
    """.trimIndent()

    private val otherCsv = """
        1756300000,99.0,536870912,1073741824,268435456,1073741824,1000,500,10,20,0.42,42.5
        1756300060,98.0,566870912,1073741824,268435456,1073741824,1100,600,11,21,0.44,42.5
    """.trimIndent()

    private class Scripted(private val answers: List<Result<String>>) : SSHCommandRunner {
        var reads = 0
        override suspend fun run(command: String, host: SSHHostID, timeout: Duration): ExecResult {
            val answer = answers[minOf(reads, answers.size - 1)]
            reads += 1
            return ExecResult(exitCode = 0, stdout = answer.getOrThrow(), stderr = "")
        }
        override fun stream(command: String, host: SSHHostID, timeout: Duration): Flow<ExecChunk> = emptyFlow()
        override suspend fun fireAndForget(command: String, host: SSHHostID) = Unit
        override suspend fun disconnect() = Unit
    }

    private class ParkingSleeper : SleepProvider {
        override suspend fun sleep(duration: Duration): Unit = awaitCancellation()
    }

    @Test
    fun `a bucket file becomes points`() = runTest(StandardTestDispatcher()) {
        val model = HistoryViewModel(
            scope = CoroutineScope(coroutineContext),
            runners = { Scripted(listOf(Result.success(csv))) },
            sleeper = ParkingSleeper(),
        )
        model.show(server(), SSHHostID.VPS, HistoryRange.HOUR)
        runCurrent()

        val state = model.state.value
        assertEquals(2, state.points.size)
        assertEquals(12.5, state.points.first().cpuPercent)
        assertTrue(state.hasAnswered)
        assertNull(state.errorMessage)
        model.stop()
    }

    /** An empty answer is an ANSWER */
    @Test
    fun `no collector reads as answered and empty`() = runTest(StandardTestDispatcher()) {
        val model = HistoryViewModel(
            scope = CoroutineScope(coroutineContext),
            runners = { Scripted(listOf(Result.success(""))) },
            sleeper = ParkingSleeper(),
        )
        model.show(server(), SSHHostID.VPS, HistoryRange.HOUR)
        runCurrent()

        val state = model.state.value
        assertTrue(state.points.isEmpty())
        assertTrue(state.hasAnswered, "an empty file is not the same as not having asked")
        assertNull(state.errorMessage)
        assertTrue(!state.isLoading)
        model.stop()
    }

    @Test
    fun `a failure keeps the last chart and speaks up only on an empty one`() =
        runTest(StandardTestDispatcher()) {
            val released = mutableListOf<String>()
            var reads = 0
            val model = HistoryViewModel(
                scope = CoroutineScope(coroutineContext),
                runners = {
                    reads += 1
                    if (reads == 1) Scripted(listOf(Result.success(csv)))
                    else Scripted(listOf(Result.failure(RuntimeException("connection reset"))))
                },
                release = { released += it.id },
                sleeper = object : SleepProvider {
                    var waits = 0
                    override suspend fun sleep(duration: Duration) {
                        waits += 1
                        if (waits >= 2) awaitCancellation()
                    }
                },
            )
            model.show(server(), SSHHostID.VPS, HistoryRange.HOUR)
            runCurrent()

            val afterFailure = model.state.value
            assertEquals(2, afterFailure.points.size, "the chart must survive one failed tick")
            assertNull(afterFailure.errorMessage)
            assertEquals(listOf("H-1"), released, "a failed read drops the session reference")
            model.stop()

            val empty = HistoryViewModel(
                scope = CoroutineScope(coroutineContext),
                runners = { Scripted(listOf(Result.failure(RuntimeException("host key mismatch")))) },
                sleeper = ParkingSleeper(),
            )
            empty.show(server("H-2"), SSHHostID.VPS, HistoryRange.HOUR)
            runCurrent()
            assertEquals("host key mismatch", empty.state.value.errorMessage)
            empty.stop()
        }

    /** Two windows over the same file are one read */
    @Test
    fun `switching to a window with the same bucket does not read again`() =
        runTest(StandardTestDispatcher()) {
            var reads = 0
            val model = HistoryViewModel(
                scope = CoroutineScope(coroutineContext),
                runners = { reads += 1; Scripted(listOf(Result.success(csv))) },
                sleeper = ParkingSleeper(),
            )
            val deployment = server()
            model.show(deployment, SSHHostID.VPS, HistoryRange.TEN_MINUTES)
            runCurrent()
            model.show(deployment, SSHHostID.VPS, HistoryRange.THIRTY_MINUTES)
            runCurrent()
            assertEquals(1, reads, "the same file must not be fetched twice")

            model.show(deployment, SSHHostID.VPS, HistoryRange.DAY)
            runCurrent()
            assertEquals(2, reads)
            model.stop()
        }

    /** Two readers, two selections */
    @Test
    fun `a detached reader has its own selection and leaves the parent's alone`() =
        runTest(StandardTestDispatcher()) {
            var reads = 0
            val model = HistoryViewModel(
                scope = CoroutineScope(coroutineContext),
                runners = { deployment ->
                    reads += 1
                    Scripted(listOf(Result.success(if (deployment.id == "A") csv else otherCsv)))
                },
                sleeper = ParkingSleeper(),
            )
            val inline = model.detached()

            model.show(server("A"), SSHHostID.VPS, HistoryRange.HOUR)
            runCurrent()
            inline.show(server("B"), SSHHostID.VPS, HistoryRange.DAY)
            runCurrent()
            assertEquals(2, reads)

            assertEquals(12.5, model.state.value.points.first().cpuPercent)
            assertEquals(99.0, inline.state.value.points.first().cpuPercent,
                "the second reader must not be drawing the first one's machine")

            // The parent is still parked on its own selection: a shared model
            // would have had it taken away and would go back to the server.
            model.show(server("A"), SSHHostID.VPS, HistoryRange.HOUR)
            runCurrent()
            assertEquals(2, reads, "the parent's selection must have survived the second reader")

            inline.stop()
            model.stop()
        }

    /** Another machine is another file: the selection is per host, not global. */
    @Test
    fun `a different server reads again`() = runTest(StandardTestDispatcher()) {
        var reads = 0
        val model = HistoryViewModel(
            scope = CoroutineScope(coroutineContext),
            runners = { reads += 1; Scripted(listOf(Result.success(csv))) },
            sleeper = ParkingSleeper(),
        )
        model.show(server("A"), SSHHostID.VPS, HistoryRange.HOUR)
        runCurrent()
        model.show(server("B"), SSHHostID.VPS, HistoryRange.HOUR)
        runCurrent()
        assertEquals(2, reads)
        assertNotNull(model.state.value.points.firstOrNull())
        model.stop()
    }
}
