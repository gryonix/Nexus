package com.skaymer.gryonixnexus.app.metrics

import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.ExecChunk
import com.skaymer.gryonixnexus.servercontrol.ExecResult
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryBucket
import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryPoint
import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryReading
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.SleepProvider
import java.time.Instant
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

/** The metrics board */
class MetricsBoardViewModelTests {
    private fun server(id: String) = Deployment(
        id = id,
        name = id,
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
    )

    private fun panel(
        id: String,
        deployment: String = "S-1",
        host: SSHHostID = SSHHostID.VPS,
        metrics: List<HistoryMetric> = listOf(HistoryMetric.CPU),
        range: HistoryRange = HistoryRange.HOUR,
    ) = MetricPanel.of(id, server(deployment), host, metrics, range)

    private fun point(at: Long) = MetricsHistoryPoint(
        date = Instant.ofEpochSecond(at),
        cpuPercent = 12.0,
        memUsedBytes = 1,
        memTotalBytes = 2,
        diskUsedBytes = 1,
        diskTotalBytes = 4,
        netReceivedPerSecond = null,
        netSentPerSecond = null,
        diskReadPerSecond = null,
        diskWrittenPerSecond = null,
        load1 = 0.1,
        temperatureCelsius = null,
    )

    private object Idle : SSHCommandRunner {
        override suspend fun run(command: String, host: SSHHostID, timeout: Duration) =
            ExecResult(0, "", "")

        override fun stream(command: String, host: SSHHostID, timeout: Duration): Flow<ExecChunk> =
            emptyFlow()

        override suspend fun fireAndForget(command: String, host: SSHHostID) = Unit

        override suspend fun disconnect() = Unit
    }

    private class Reading(
        val body: suspend (MetricsHistoryBucket, SSHHostID) -> List<MetricsHistoryPoint>,
    ) : MetricsHistoryReading {
        override suspend fun history(
            bucket: MetricsHistoryBucket,
            host: SSHHostID,
        ): List<MetricsHistoryPoint> = body(bucket, host)
    }

    private object Never : SleepProvider {
        override suspend fun sleep(duration: Duration) = CompletableDeferred<Unit>().await()
    }

    private class Ticks(private var ticks: Int) : SleepProvider {
        val slept = AtomicInteger()

        override suspend fun sleep(duration: Duration) {
            slept.incrementAndGet()
            if (ticks-- <= 0) CompletableDeferred<Unit>().await()
        }
    }

    private fun model(
        scope: CoroutineScope,
        read: suspend (Deployment, SSHHostID, MetricsHistoryBucket) -> List<MetricsHistoryPoint> =
            { _, _, _ -> listOf(point(0)) },
        onRelease: () -> Unit = {},
        sleeper: SleepProvider = Never,
    ) = MetricsBoardViewModel(
        scope = scope,
        runners = { Idle },
        release = { onRelease() },
        readers = { deployment, host, _ ->
            Reading { bucket, _ -> read(deployment, host, bucket) }
        },
        sleeper = sleeper,
    )

    // -------------------------------------------------------------- Sharing

    @Test
    fun `two tiles of one machine and period cost one read`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val reads = AtomicInteger()
        val model = model(scope, read = { _, _, _ -> reads.incrementAndGet(); listOf(point(0)) })

        model.update(
            listOf(
                panel("P-1", metrics = listOf(HistoryMetric.CPU)),
                panel("P-2", metrics = listOf(HistoryMetric.MEMORY)),
            ),
            listOf(server("S-1")),
        )
        advanceUntilIdle()

        assertEquals(1, reads.get())
        assertEquals(1, model.state.value.points.size)
    }

    @Test
    fun `tiles on different periods are read separately`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val buckets = mutableListOf<MetricsHistoryBucket>()
        val model = model(scope, read = { _, _, bucket -> buckets += bucket; listOf(point(0)) })

        model.update(
            listOf(
                panel("P-1", range = HistoryRange.HOUR),
                panel("P-2", range = HistoryRange.WEEK),
            ),
            listOf(server("S-1")),
        )
        advanceUntilIdle()

        assertEquals(
            setOf(MetricsHistoryBucket.ONE_MINUTE, MetricsHistoryBucket.ONE_HOUR),
            buckets.toSet(),
        )
    }

    @Test
    fun `every tile is read at once`() {
        val running = AtomicInteger()
        val peak = AtomicInteger()
        val started = java.util.concurrent.CountDownLatch(3)
        val release = java.util.concurrent.CountDownLatch(1)
        val scope = CoroutineScope(kotlinx.coroutines.Dispatchers.Default)
        val model = MetricsBoardViewModel(
            scope = scope,
            runners = { Idle },
            readers = { _, _, _ ->
                Reading { _, _ ->
                    val now = running.incrementAndGet()
                    peak.updateAndGet { maxOf(it, now) }
                    started.countDown()
                    release.await()
                    running.decrementAndGet()
                    listOf(point(0))
                }
            },
            sleeper = Never,
        )

        model.update(
            listOf(
                panel("P-1", deployment = "S-1"),
                panel("P-2", deployment = "S-2"),
                panel("P-3", deployment = "S-3"),
            ),
            listOf(server("S-1"), server("S-2"), server("S-3")),
        )
        assertTrue(
            started.await(5, java.util.concurrent.TimeUnit.SECONDS),
            "the three reads never overlapped: peak was ${peak.get()}",
        )
        release.countDown()
        assertEquals(3, peak.get())
        scope.cancel()
    }

    // -------------------------------------------------------------- Failures

    @Test
    fun `one unreachable server does not take the board down`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val model = model(scope, read = { deployment, _, _ ->
            if (deployment.id == "S-2") error("no route to host") else listOf(point(0))
        })

        model.update(
            listOf(panel("P-1", deployment = "S-1"), panel("P-2", deployment = "S-2")),
            listOf(server("S-1"), server("S-2")),
        )
        advanceUntilIdle()

        val state = model.state.value
        assertEquals("no route to host", state.errors["S-2"])
        assertNull(state.errors["S-1"])
        assertEquals(1, state.points.values.single().size)
    }

    @Test
    fun `a failed tick keeps the chart and stays quiet`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        var fail = false
        val model = model(scope, read = { _, _, _ ->
            if (fail) error("connection lost") else listOf(point(0), point(10))
        })
        val panels = listOf(panel("P-1"))

        model.update(panels, listOf(server("S-1")))
        advanceUntilIdle()
        assertEquals(2, model.state.value.points.values.single().size)

        fail = true
        model.refresh()
        advanceUntilIdle()

        assertEquals(2, model.state.value.points.values.single().size)
        assertNull(model.state.value.errors["S-1"], "a stale chart must not carry an error too")
    }

    /** A server that answers again is not still broken */
    @Test
    fun `a server that comes back stops reporting the tick it missed`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        var fail = true
        val model = model(scope, read = { _, _, _ ->
            if (fail) error("no route to host") else listOf(point(0))
        })
        model.update(listOf(panel("P-1")), listOf(server("S-1")))
        advanceUntilIdle()
        assertEquals("no route to host", model.state.value.errors["S-1"])

        fail = false
        model.refresh()
        advanceUntilIdle()
        assertNull(model.state.value.errors["S-1"])
    }

    @Test
    fun `a dropped session is released so the next tick redials`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        var released = 0
        val model = model(
            scope,
            read = { _, _, _ -> error("channel closed") },
            onRelease = { released += 1 },
        )
        model.update(listOf(panel("P-1")), listOf(server("S-1")))
        advanceUntilIdle()
        assertEquals(1, released)
    }

    // ------------------------------------------------------- What a tile says

    @Test
    fun `a tile that has not been read is not a machine without a collector`() {
        val one = panel("P-1")
        val tile = MetricsBoardViewModel.tiles(listOf(one), MetricsBoardState()).single()
        assertFalse(tile.saysThereIsNone)
        assertNull(tile.errorMessage)
        assertEquals(emptyList(), tile.points)
    }

    @Test
    fun `an answered empty read is the machine saying it has no history`() {
        val one = panel("P-1")
        val state = MetricsBoardState(
            points = mapOf(one.source to emptyList()),
            hasAnswered = true,
        )
        assertTrue(MetricsBoardViewModel.tiles(listOf(one), state).single().saysThereIsNone)
    }

    @Test
    fun `a failed read never says the machine has no history`() {
        val one = panel("P-1")
        val state = MetricsBoardState(
            points = mapOf(one.source to emptyList()),
            errors = mapOf("S-1" to "no route to host"),
            hasAnswered = true,
        )
        val tile = MetricsBoardViewModel.tiles(listOf(one), state).single()
        assertFalse(tile.saysThereIsNone)
        assertEquals("no route to host", tile.errorMessage)
    }

    @Test
    fun `a tile with points does not carry its server's error`() {
        val hour = panel("P-1", range = HistoryRange.HOUR)
        val week = panel("P-2", range = HistoryRange.WEEK)
        val state = MetricsBoardState(
            points = mapOf(hour.source to listOf(point(0))),
            errors = mapOf("S-1" to "read timed out"),
            hasAnswered = true,
        )
        val tiles = MetricsBoardViewModel.tiles(listOf(hour, week), state)
        assertNull(tiles[0].errorMessage)
        assertEquals("read timed out", tiles[1].errorMessage)
    }

    // ------------------------------------------------------------ The reload

    /**
     * The board's inputs are two flows that republish for their own reasons,
     * and a poll loop torn down and rebuilt on each of those is a burst of
     * handshakes with no new question behind it.
     */
    @Test
    fun `an update that asks for the same reads does not start over`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val reads = AtomicInteger()
        val model = model(scope, read = { _, _, _ -> reads.incrementAndGet(); listOf(point(0)) })
        val panels = listOf(panel("P-1"))

        model.update(panels, listOf(server("S-1")))
        advanceUntilIdle()
        assertEquals(1, reads.get())

        model.update(panels, listOf(server("S-1")))
        advanceUntilIdle()
        assertEquals(1, reads.get())
    }

    @Test
    fun `points of a source nobody shows are dropped`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val model = model(scope)
        val hour = panel("P-1", range = HistoryRange.HOUR)
        val week = panel("P-2", range = HistoryRange.WEEK)

        model.update(listOf(hour, week), listOf(server("S-1")))
        advanceUntilIdle()
        assertEquals(2, model.state.value.points.size)

        model.update(listOf(hour), listOf(server("S-1")))
        advanceUntilIdle()
        assertEquals(setOf(hour.source), model.state.value.points.keys)
    }

    @Test
    fun `points of a removed tile are dropped before the next read lands`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        var park = false
        val model = model(scope, read = { _, _, _ ->
            if (park) CompletableDeferred<List<MetricsHistoryPoint>>().await() else listOf(point(0))
        })
        val hour = panel("P-1", range = HistoryRange.HOUR)
        val week = panel("P-2", range = HistoryRange.WEEK)

        model.update(listOf(hour, week), listOf(server("S-1")))
        advanceUntilIdle()
        assertEquals(2, model.state.value.points.size)

        park = true
        model.update(listOf(hour), listOf(server("S-1")))
        runCurrent()
        assertEquals(setOf(hour.source), model.state.value.points.keys)
    }

    /** An empty board reads nothing at all */
    @Test
    fun `an empty board asks no server anything`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val reads = AtomicInteger()
        val model = model(scope, read = { _, _, _ -> reads.incrementAndGet(); listOf(point(0)) })

        model.update(emptyList(), listOf(server("S-1")))
        advanceUntilIdle()
        assertEquals(0, reads.get())
        assertFalse(model.state.value.hasAnswered)

        model.refresh()
        advanceUntilIdle()
        assertEquals(0, reads.get())
        assertFalse(model.state.value.hasAnswered, "an empty board called itself answered")
    }

    @Test
    fun `a tile whose server is unknown is not read`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val reads = AtomicInteger()
        val model = model(scope, read = { _, _, _ -> reads.incrementAndGet(); listOf(point(0)) })

        model.update(listOf(panel("P-1", deployment = "S-9")), listOf(server("S-1")))
        advanceUntilIdle()
        assertEquals(0, reads.get())
    }

    @Test
    fun `the board reads again on the next tick`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val reads = AtomicInteger()
        val model = model(
            scope,
            read = { _, _, _ -> reads.incrementAndGet(); listOf(point(0)) },
            sleeper = Ticks(2),
        )
        model.update(listOf(panel("P-1")), listOf(server("S-1")))
        advanceUntilIdle()
        assertEquals(3, reads.get(), "the loop read once and stopped")
    }

    /** Stopping ends the loop; the next tick never comes */
    @Test
    fun `stopping ends the polling`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val reads = AtomicInteger()
        val sleeper = Ticks(100)
        val model = model(
            scope,
            read = { _, _, _ -> reads.incrementAndGet(); listOf(point(0)) },
            sleeper = sleeper,
        )
        model.update(listOf(panel("P-1")), listOf(server("S-1")))
        runCurrent()
        model.stop()
        val seenReads = reads.get()
        val seenSleeps = sleeper.slept.get()
        advanceUntilIdle()

        assertEquals(seenReads, reads.get())
        assertEquals(seenSleeps, sleeper.slept.get(), "the loop is still going round")
    }
}
