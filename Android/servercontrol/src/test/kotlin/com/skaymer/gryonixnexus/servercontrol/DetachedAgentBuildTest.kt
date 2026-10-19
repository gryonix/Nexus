package com.skaymer.gryonixnexus.servercontrol

import java.io.IOException
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class DetachedAgentBuildTest {
    @Test
    fun `the reader counts lines across cut chunks and finds the exit code`() {
        val reader = BuildLogReader()
        assertEquals(emptyList(), reader.feed("Compiling ser"))
        assertEquals(listOf("Compiling serde", "Finished"), reader.feed("de\r\n\nFinished\n"))
        assertEquals(3, reader.linesSeen)
        assertNull(reader.exitCode)
        assertEquals(emptyList(), reader.feed("${DetachedAgentBuild.EXIT_MARKER}0\n"))
        assertEquals(0, reader.exitCode)
        assertEquals("Compiling serde\nFinished\n", reader.transcript)
    }

    @Test
    fun `the build runs in its own session and logs beside the home`() {
        val build = DetachedAgentBuild("/home/it's")
        val start = build.startCommand(null, "/opt/wrapper.sh")
        assertTrue(start.startsWith("bash -c "))
        assertTrue("setsid nohup bash -c" in start)
        assertTrue("sudo -n /opt/wrapper.sh" in start)
        assertFalse("R=\$?" in start)
        assertTrue("tail -n +42" in build.followCommand(42))
    }

    @Test
    fun `a dropped link is reopened from the first unread line`() = runTest {
        val runner = Scripted(listOf("one\ntwo\nthr" to true, "three\n${DetachedAgentBuild.EXIT_MARKER}0\n" to false))
        var reconnects = 0
        var backs = 0
        val outcome = DetachedAgentBuild("/root", 1.milliseconds)
            .follow(runner, SSHHostID.VPS, {}, onReconnect = { reconnects++ }, onReconnected = { backs++ })
        assertEquals(DetachedAgentBuild.Outcome(0, "one\ntwo\nthree\n"), outcome)
        assertEquals(1, reconnects)
        assertEquals(1, backs, "the link coming back is reported once")
        assertTrue("tail -n +1 " in runner.streamed[0])
        assertTrue("tail -n +3 " in runner.streamed[1], "the cut line is read again")
    }

    @Test
    fun `a build that dies without the marker is a failure`() = runTest {
        val runner = Scripted(listOf("killed\n" to false))
        val outcome = DetachedAgentBuild("/root", 1.milliseconds).follow(runner, SSHHostID.VPS, {}, onReconnect = {})
        assertEquals(DetachedAgentBuild.Outcome(-1, "killed\n"), outcome)
    }

    private class Scripted(streams: List<Pair<String, Boolean>>) : SSHCommandRunner {
        private val queue = ArrayDeque(streams)
        val streamed = mutableListOf<String>()

        override suspend fun run(command: String, host: SSHHostID, timeout: Duration) = ExecResult(0, "", "")

        override fun stream(command: String, host: SSHHostID, timeout: Duration): Flow<ExecChunk> {
            streamed += command
            val (text, fails) = queue.removeFirstOrNull() ?: ("" to false)
            return flow {
                emit(ExecChunk.Stdout(text))
                emit(ExecChunk.Stderr("tail: noise\n"))
                if (fails) throw IOException("connection lost")
            }
        }

        override suspend fun fireAndForget(command: String, host: SSHHostID) = Unit
        override suspend fun disconnect() = Unit
    }
}
