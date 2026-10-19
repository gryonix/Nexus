package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.ExecChunk
import com.skaymer.gryonixnexus.servercontrol.ExecResult
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.NodeCapability
import com.skaymer.gryonixnexus.servercontrol.addingNode
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.SleepProvider
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

/** The poll loop behind the server cards */
class FleetMetricsTests {
    // ------------------------------------------------------------- Fixtures

    private fun single(id: String = "ONE-1", name: String = "one") = Deployment(
        id = id,
        name = name,
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.20", user = "root"),
    )

    private fun pair(id: String = "PAIR-1") = Deployment(
        id = id,
        name = "pair",
        topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.10", user = "control"),
        homeWGAddress = "10.8.0.2",
    )

    /** A machine added by hand, reachable through [parent] */
    private fun worker(
        id: String,
        parent: String,
        name: String = "spare",
        host: String = "10.9.0.9",
    ) = DeploymentNode(
        id = id,
        name = name,
        endpoint = HostEndpoint(host = host, user = "root"),
        capabilities = setOf(NodeCapability.WORKER),
        routedThrough = parent,
    )

    private fun probeOutput(cpuIdle: Int = 8000, uptime: Double = 1000.0): String = """
        @@STAT@@
        cpu  1000 50 300 $cpuIdle 200 0 25 10 0 0
        cpu0 500 25 150 4000 100 0 12 5 0 0
        intr 12345
        @@MEM@@
        MemTotal:         430080 kB
        MemFree:           51200 kB
        MemAvailable:     174080 kB
        SwapTotal:        102400 kB
        SwapFree:          92160 kB
        @@UPTIME@@
        $uptime 15130655.92
        @@LOAD@@
        0.42 0.31 0.25 1/123 4567
        @@NET@@
        Inter-|   Receive                                                |  Transmit
         face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets
            lo: 999999    9999    0    0    0     0          0         0  999999    9999    0    0    0     0       0          0
          eth0: 1000000   66666    0    0    0     0          0         0 500000    55555    0    0    0     0       0          0
        @@DF@@
        Mounted on     1B-blocks       Used Use%
        /            45000000000 5364000000  12%
        @@NPROC@@
        2
    """.trimIndent()

    private class ScriptedRunner(
        private val script: Map<SSHHostID, List<Result<String>>>,
    ) : SSHCommandRunner {
        val calls = mutableMapOf<SSHHostID, Int>()

        override suspend fun run(command: String, host: SSHHostID, timeout: Duration): ExecResult {
            val index = calls.getOrDefault(host, 0)
            calls[host] = index + 1
            val answers = script[host] ?: error("the script says nothing about $host")
            val answer = answers[minOf(index, answers.size - 1)]
            return ExecResult(exitCode = 0, stdout = answer.getOrThrow(), stderr = "")
        }

        override fun stream(command: String, host: SSHHostID, timeout: Duration): Flow<ExecChunk> =
            emptyFlow()

        override suspend fun fireAndForget(command: String, host: SSHHostID) = Unit

        override suspend fun disconnect() = Unit
    }

    private class Recorder(private val parkAfter: Int) : SleepProvider {
        val slept = mutableListOf<Duration>()

        override suspend fun sleep(duration: Duration) {
            slept += duration
            if (slept.size >= parkAfter) awaitCancellation()
        }
    }

    private fun drive(
        deployment: Deployment,
        script: Map<SSHHostID, List<Result<String>>>,
        ticks: Int,
        released: MutableList<String> = mutableListOf(),
        runners: (suspend (Deployment) -> SSHCommandRunner)? = null,
    ): Pair<FleetMetrics, Recorder> {
        val recorder = Recorder(ticks)
        var metrics: FleetMetrics? = null
        runTest(StandardTestDispatcher()) {
            val scope = CoroutineScope(coroutineContext)
            val runner = ScriptedRunner(script)
            metrics = FleetMetrics(
                scope = scope,
                runners = runners ?: { runner },
                release = { released += it.id },
                sleeper = recorder,
            )
            metrics!!.sync(listOf(deployment))
            runCurrent()
            metrics!!.stopAll()
        }
        return metrics!! to recorder
    }

    private class ParkingSleeper : SleepProvider {
        override suspend fun sleep(duration: Duration): Unit = awaitCancellation()
    }

    private val vps = SSHHostID.VPS
    private val home = SSHHostID.HOME

    // ---------------------------------------------------------------- Rates

    /** Two samples, or no rate */
    @Test
    fun `the first reading carries no cpu percentage and the second does`() {
        val deployment = single()
        val (metrics, _) = drive(
            deployment,
            mapOf(vps to listOf(
                Result.success(probeOutput(cpuIdle = 8000, uptime = 1000.0)),
                Result.success(probeOutput(cpuIdle = 8100, uptime = 1010.0)),
            )),
            ticks = 2,
        )
        val state = metrics.card(deployment.id).value.getValue(vps)
        assertNotNull(state.snapshot)
        assertNotNull(state.snapshot!!.cpuPercent)
    }

    @Test
    fun `a single reading is honest that it has no rate yet`() {
        val deployment = single()
        val (metrics, _) = drive(
            deployment,
            mapOf(vps to listOf(Result.success(probeOutput()))),
            ticks = 1,
        )
        assertNull(metrics.card(deployment.id).value.getValue(vps).snapshot!!.cpuPercent)
    }

    @Test
    fun `the reading after a failure has no rate to show`() {
        val deployment = single()
        val (metrics, _) = drive(
            deployment,
            mapOf(vps to listOf(
                Result.success(probeOutput(cpuIdle = 8000, uptime = 1000.0)),
                Result.failure(RuntimeException("connection reset")),
                Result.success(probeOutput(cpuIdle = 9000, uptime = 4600.0)),
            )),
            ticks = 3,
        )
        val state = metrics.card(deployment.id).value.getValue(vps)
        assertNotNull(state.snapshot)
        assertNull(state.snapshot!!.cpuPercent)
        assertNull(state.errorMessage)
    }

    // ------------------------------------------------------------- Back-off

    @Test
    fun `a healthy loop keeps its interval`() {
        val deployment = single()
        val (_, recorder) = drive(
            deployment,
            mapOf(vps to listOf(Result.success(probeOutput()))),
            ticks = 3,
        )
        assertEquals(listOf(5.seconds, 5.seconds, 5.seconds), recorder.slept)
    }

    @Test
    fun `failures back off and stop doubling at forty seconds`() {
        val deployment = single()
        val (_, recorder) = drive(
            deployment,
            mapOf(vps to listOf(Result.failure(RuntimeException("down")))),
            ticks = 5,
        )
        assertEquals(
            listOf(10.seconds, 20.seconds, 40.seconds, 40.seconds, 40.seconds),
            recorder.slept
        )
    }

    @Test
    fun `a clean tick resets the back off`() {
        val deployment = single()
        val (_, recorder) = drive(
            deployment,
            mapOf(vps to listOf(
                Result.failure(RuntimeException("down")),
                Result.failure(RuntimeException("down")),
                Result.success(probeOutput()),
            )),
            ticks = 3,
        )
        assertEquals(listOf(10.seconds, 20.seconds, 5.seconds), recorder.slept)
    }

    // ------------------------------------------------------- Which half fails

    @Test
    fun `only an entry machine failure releases the session`() {
        val deployment = pair()
        val released = mutableListOf<String>()
        drive(
            deployment,
            mapOf(
                vps to listOf(Result.success(probeOutput())),
                home to listOf(Result.failure(RuntimeException("home is asleep"))),
            ),
            ticks = 2,
            released = released,
        )
        assertTrue(released.isEmpty(), "the far half failing must not drop the session")

        val alsoReleased = mutableListOf<String>()
        drive(
            deployment,
            mapOf(
                vps to listOf(Result.failure(RuntimeException("relay is down"))),
                home to listOf(Result.failure(RuntimeException("unreachable"))),
            ),
            ticks = 2,
            released = alsoReleased,
        )
        assertEquals(listOf(deployment.id, deployment.id), alsoReleased)
    }

    /** A half-failing pair still shows the working half's numbers */
    @Test
    fun `the working machine of a failing pair keeps its readings`() {
        val deployment = pair()
        val (metrics, _) = drive(
            deployment,
            mapOf(
                vps to listOf(Result.success(probeOutput())),
                home to listOf(Result.failure(RuntimeException("home is asleep"))),
            ),
            ticks = 1,
        )
        val card = metrics.card(deployment.id).value
        assertNotNull(card.getValue(vps).snapshot)
        assertEquals("home is asleep", card.getValue(home).errorMessage)
    }

    // ----------------------------------------------------------- Reconnects

    /** A rename keeps the live session */
    @Test
    fun `a rename keeps the poller and a new address replaces it`() = runTest(StandardTestDispatcher()) {
        val scope = CoroutineScope(coroutineContext)
        var built = 0
        val metrics = FleetMetrics(
            scope = scope,
            runners = { built += 1; ScriptedRunner(mapOf(vps to listOf(Result.success(probeOutput())))) },
            sleeper = ParkingSleeper(),
        )
        val deployment = single()
        metrics.sync(listOf(deployment))
        runCurrent()
        metrics.sync(listOf(deployment.copy(name = "renamed")))
        runCurrent()
        metrics.stopAll()
        assertEquals(1, built, "a rename must not rebuild the session")

        var rebuilt = 0
        val second = FleetMetrics(
            scope = scope,
            runners = { rebuilt += 1; ScriptedRunner(mapOf(vps to listOf(Result.success(probeOutput())))) },
            sleeper = ParkingSleeper(),
        )
        second.sync(listOf(deployment))
        runCurrent()
        second.sync(listOf(deployment.copy(entry = HostEndpoint(host = "203.0.113.99", user = "root"))))
        runCurrent()
        second.stopAll()
        assertTrue(rebuilt >= 2, "a new address must rebuild the session, got $rebuilt")
    }

    @Test
    fun `a quiet server shows no connection, and long silence rebuilds its session once`() = runTest(StandardTestDispatcher()) {
        val scope = CoroutineScope(coroutineContext)
        var built = 0
        var now = 1_000_000L
        val watch = SilenceWatch(waits = { ConnectionWaits(15, 90) }, reason = { "silent $it" })
        val metrics = FleetMetrics(
            scope = scope,
            runners = { built += 1; ScriptedRunner(mapOf(vps to listOf(Result.success(probeOutput())))) },
            sleeper = ParkingSleeper(),
            silence = watch,
            clock = { now },
        )
        val deployment = single()
        metrics.sync(listOf(deployment))
        runCurrent()
        assertNull(metrics.card(deployment.id).value[vps]?.errorMessage)

        metrics.markSilentHosts(watch, now + 20_000)
        assertEquals("silent 15", metrics.card(deployment.id).value[vps]?.errorMessage)
        assertEquals(1, built, "short silence must not reconnect")

        metrics.markSilentHosts(watch, now + 100_000)
        runCurrent()
        assertEquals(2, built, "long silence rebuilds the session")

        metrics.markSilentHosts(watch, now + 150_000)
        runCurrent()
        metrics.stopAll()
        assertEquals(2, built, "reconnects are spaced out")
    }

    @Test
    fun `a second machine added also restarts the poll loop`() = runTest(StandardTestDispatcher()) {
        val scope = CoroutineScope(coroutineContext)
        var built = 0
        val metrics = FleetMetrics(
            scope = scope,
            runners = { built += 1; ScriptedRunner(mapOf(vps to listOf(Result.success(probeOutput())))) },
            sleeper = ParkingSleeper(),
        )
        val deployment = single()
        val entry = deployment.nodes.single()

        metrics.sync(listOf(deployment))
        runCurrent()
        assertEquals(1, built, "the fleet's own machine is polled from the start")

        val one = deployment.addingNode(worker("dddddddd-dddd-dddd-dddd-dddddddddddd", entry.id))
        metrics.sync(listOf(one))
        runCurrent()
        assertEquals(2, built, "the first machine added must restart the loop")

        val two = one.addingNode(worker("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee", entry.id, host = "10.9.0.10"))
        metrics.sync(listOf(two))
        runCurrent()
        metrics.stopAll()
        assertEquals(3, built, "the second machine added must restart the loop too")
    }

    @Test
    fun `renaming an added machine keeps the poll loop`() = runTest(StandardTestDispatcher()) {
        val scope = CoroutineScope(coroutineContext)
        var built = 0
        val metrics = FleetMetrics(
            scope = scope,
            runners = { built += 1; ScriptedRunner(mapOf(vps to listOf(Result.success(probeOutput())))) },
            sleeper = ParkingSleeper(),
        )
        val deployment = single()
        val entry = deployment.nodes.single()
        val grown = deployment.addingNode(
            worker("dddddddd-dddd-dddd-dddd-dddddddddddd", entry.id, name = "spare"),
        )

        metrics.sync(listOf(grown))
        runCurrent()
        val renamed = grown.copy(
            storedNodes = grown.nodes.map { node ->
                if (node.legacySlot == null) node.copy(name = "the spare") else node
            },
        )
        metrics.sync(listOf(renamed))
        runCurrent()
        metrics.stopAll()
        assertEquals(1, built, "renaming a machine must not rebuild the session")
    }

    @Test
    fun `resuming after the app went away polls again`() = runTest(StandardTestDispatcher()) {
        val scope = CoroutineScope(coroutineContext)
        var built = 0
        val metrics = FleetMetrics(
            scope = scope,
            runners = {
                built += 1
                ScriptedRunner(mapOf(vps to listOf(Result.success(probeOutput()))))
            },
            sleeper = ParkingSleeper(),
        )
        val deployment = single()
        metrics.sync(listOf(deployment))
        runCurrent()
        assertEquals(1, built)

        metrics.stopAll()
        runCurrent()
        metrics.resume(listOf(deployment))
        runCurrent()
        assertEquals(2, built, "the loop must be running again after a resume")
        metrics.stopAll()
    }

    @Test
    fun `retrying failed hosts leaves a healthy server alone`() = runTest(StandardTestDispatcher()) {
        val scope = CoroutineScope(coroutineContext)
        val healthy = single("OK-1")
        val broken = single("BAD-1", name = "broken")
        val builds = mutableMapOf<String, Int>()
        val metrics = FleetMetrics(
            scope = scope,
            runners = { deployment ->
                builds[deployment.id] = builds.getOrDefault(deployment.id, 0) + 1
                if (deployment.id == healthy.id) {
                    ScriptedRunner(mapOf(vps to listOf(Result.success(probeOutput()))))
                } else {
                    ScriptedRunner(mapOf(vps to listOf(Result.failure(RuntimeException("down")))))
                }
            },
            sleeper = ParkingSleeper(),
        )
        metrics.sync(listOf(healthy, broken))
        runCurrent()
        val healthyBuilds = builds.getValue(healthy.id)

        metrics.retryFailedHosts()
        runCurrent()
        metrics.stopAll()
        assertEquals(healthyBuilds, builds[healthy.id], "a card showing numbers must not reconnect")
    }
}
