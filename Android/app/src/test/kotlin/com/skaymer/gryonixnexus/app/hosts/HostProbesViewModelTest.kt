package com.skaymer.gryonixnexus.app.hosts

import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.DiskMount
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.MemoryUsage
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.NodeCapability
import com.skaymer.gryonixnexus.servercontrol.WGInterfaceStatus
import com.skaymer.gryonixnexus.servercontrol.WGStatus
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class HostProbesViewModelTest {
    private fun relayPair(): Deployment = Deployment(
        id = "00000000-0000-0000-0000-0000000000B2",
        name = "b5.example.net",
        topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        domain = "b5.example.net",
        entry = HostEndpoint(host = "203.0.113.20", user = "server-user"),
        homeWGAddress = "10.8.0.2",
    )

    private fun singleHost(): Deployment = Deployment(
        id = "00000000-0000-0000-0000-0000000000A1",
        name = "example.net",
        topology = Topology.SINGLE_HOST,
        domain = "example.net",
        entry = HostEndpoint(host = "203.0.113.10", user = "server-user"),
    )

    private val someMemory = MemoryUsage(
        memTotalBytes = 4_000, memUsedBytes = 1_000,
        swapTotalBytes = 0, swapUsedBytes = 0,
    )
    private val someDisk = listOf(
        DiskMount(target = "/", sizeBytes = 100, usedBytes = 10, usedPercent = 10),
    )

    @Test
    fun `only the shipped pair's own machines are asked about WireGuard`() {
        val pair = relayPair()
        assertEquals(2, pair.nodes.size, "the relay pair should derive two machines")
        for (node in pair.nodes) {
            assertTrue(
                HostProbesViewModel.showsWireGuard(pair, node),
                "${node.legacySlot} is half of the tunnel and must be asked",
            )
        }

        val added = DeploymentNode(
            id = "00000000-0000-0000-0000-0000000000C3",
            name = "worker",
            endpoint = HostEndpoint(host = "10.8.0.3", user = "server-user"),
            capabilities = setOf(NodeCapability.WORKER),
        )
        assertNull(added.legacySlot, "a machine added later has no shipped slot")
        assertFalse(
            HostProbesViewModel.showsWireGuard(pair, added),
            "a machine added behind the pair has no wg0 — asking it is a probe " +
                "spent to print a red row about a tunnel that was never there",
        )

        val single = singleHost()
        for (node in single.nodes) {
            assertFalse(
                HostProbesViewModel.showsWireGuard(single, node),
                "scenario A has no tunnel at all",
            )
        }
    }

    /**
     * **A slow machine's answer must not land on the next server's block.**
     * The ordering is STATED rather than waited for: each server's probe has
     * its own gate and the second is released first, so the test measures the
     * rule instead of the scheduler — the `runTest` lesson GOTCHAS records.
     */
    @Test
    fun `an answer from the server left behind does not land on the next one`() = runTest {
        val slow = CompletableDeferred<MemoryUsage>()
        val quick = CompletableDeferred<MemoryUsage>()
        val first = singleHost()
        val second = relayPair()

        val model = HostProbesViewModel(
            scope = CoroutineScope(coroutineContext),
            disk = { _, _ -> someDisk },
            memory = { deployment, _ ->
                if (deployment.id == first.id) slow.await() else quick.await()
            },
            wireGuard = { _, _ -> WGStatus(`interface` = WGInterfaceStatus("wg0", null, null), peers = emptyList()) },
        )

        model.load(first)
        model.reset()
        model.load(second)
        quick.complete(someMemory)
        advanceUntilIdle()
        val afterSecond = model.state.value
        assertTrue(afterSecond.isNotEmpty(), "the second server never answered at all")

        slow.complete(MemoryUsage(memTotalBytes = 1, memUsedBytes = 1,
                                  swapTotalBytes = 0, swapUsedBytes = 0))
        advanceUntilIdle()
        assertEquals(
            afterSecond, model.state.value,
            "the machine left behind wrote its memory onto the server now on screen",
        )
    }

    @Test
    fun `a refused probe is a refusal and the others still land`() = runTest {
        val model = HostProbesViewModel(
            scope = CoroutineScope(coroutineContext),
            disk = { _, _ -> throw IllegalStateException("df: not found") },
            memory = { _, _ -> someMemory },
            wireGuard = { _, _ -> WGStatus(`interface` = WGInterfaceStatus("wg0", null, null), peers = emptyList()) },
        )
        model.load(singleHost())
        advanceUntilIdle()

        val host = singleHost().nodes.first().sshHost
        val state = model.state.value.getValue(host)
        assertTrue(state.hasAnswered)
        assertNotNull(state.memory, "one probe refusing must not take the others with it")
        assertNull(state.disk, "a refused disk read is not an empty disk")
        assertEquals("df: not found", state.diskFailed)
    }
}
