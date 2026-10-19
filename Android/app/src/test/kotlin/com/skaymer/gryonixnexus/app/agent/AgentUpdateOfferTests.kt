package com.skaymer.gryonixnexus.app.agent

import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class AgentUpdateOfferTests {
    private fun server(id: String) = Deployment(
        id = id,
        name = id,
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
        usesAgent = true,
    )

    private fun TestScope.offerFor(
        servers: List<Deployment>,
        now: () -> Long = { testScheduler.currentTime },
        published: suspend (Deployment) -> String? = { null },
        installed: suspend (Deployment) -> String,
    ) = AgentUpdateOffer(
        scope = CoroutineScope(StandardTestDispatcher(testScheduler)),
        fleet = { servers },
        installed = { deployment, _ -> installed(deployment) },
        install = {},
        published = { deployment, _ -> published(deployment) },
        now = now,
        retryDelayMillis = 1_000,
    )

    @Test
    fun `an outdated server gets an offer at launch`() = runTest {
        val offer = offerFor(listOf(server("old"), server("fresh"))) { if (it.id == "old") "0.0.100" else "999.0.0" }
        offer.checkOnLaunch()
        runCurrent()
        assertEquals(listOf("old"), offer.offer.value?.servers?.map { it.deployment.id })
    }

    @Test
    fun `later silences the offer only until the next start`() = runTest {
        val old = server("old")
        val first = offerFor(listOf(old)) { "0.0.100" }
        first.checkOnLaunch()
        runCurrent()
        first.later()
        first.checkOnLaunch()
        runCurrent()
        assertNull(first.offer.value, "no second window in the same run")

        first.appLeft()
        first.checkOnLaunch()
        runCurrent()
        assertNotNull(first.offer.value, "opening the app again asks again, even soon after")
    }

    @Test
    fun `a silent server does not hold the window back`() = runTest {
        val offer = offerFor(listOf(server("old"), server("stuck"))) {
            if (it.id == "stuck") delay(Long.MAX_VALUE)
            "0.0.100"
        }
        offer.checkOnLaunch()
        runCurrent()
        advanceTimeBy(AgentUpdateOffer.DEADLINE_MILLIS + 1)
        runCurrent()
        assertEquals(listOf("old"), offer.offer.value?.servers?.map { it.deployment.id })
    }

    @Test
    fun `the window opens before a slow server answers`() = runTest {
        val offer = offerFor(listOf(server("old"), server("slow"))) {
            if (it.id == "slow") delay(AgentUpdateOffer.DEADLINE_MILLIS / 2)
            if (it.id == "old") "0.0.100" else "999.0.0"
        }
        offer.checkOnLaunch()
        runCurrent()
        assertEquals(listOf("old"), offer.offer.value?.servers?.map { it.deployment.id })
    }

    @Test
    fun `coming back soon after does not ask the servers again`() = runTest {
        var asked = 0
        val offer = offerFor(listOf(server("a"))) { asked += 1; "999.0.0" }
        offer.checkOnLaunch()
        runCurrent()
        offer.checkOnLaunch()
        runCurrent()
        assertEquals(1, asked)
    }

    @Test
    fun `a server that could not be reached at start is tried again`() = runTest {
        var asked = 0
        val offer = offerFor(listOf(server("old"))) {
            asked += 1
            if (asked < 3) error("network not ready")
            "0.0.100"
        }
        offer.checkOnLaunch()
        runCurrent()
        assertNull(offer.offer.value, "the first try found nothing")
        advanceTimeBy(5_000)
        runCurrent()
        assertEquals(listOf("old"), offer.offer.value?.servers?.map { it.deployment.id })
    }

    @Test
    fun `a published update is offered when the server is not older than the app`() = runTest {
        val offer = offerFor(listOf(server("a")), published = { "999.0.0" }) { "999.0.0" }
        offer.checkOnLaunch()
        runCurrent()
        assertNull(offer.offer.value, "equal versions need no update")

        val newer = offerFor(listOf(server("a")), published = { "9999.0.0" }) { "999.0.0" }
        newer.checkOnLaunch()
        runCurrent()
        val shown = newer.offer.value
        assertEquals("9999.0.0", shown?.version)
        assertEquals(AgentUpdateOffer.Source.PUBLISHED, shown?.servers?.single()?.source)
    }
}
