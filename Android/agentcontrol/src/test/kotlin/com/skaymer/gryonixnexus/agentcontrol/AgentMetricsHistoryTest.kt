package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryBucket
import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryRouting
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.ServiceControlRoute
import gryonixnexusd.v1.MetricsHistoryPoint
import gryonixnexusd.v1.MetricsHistoryRequest
import gryonixnexusd.v1.MetricsHistoryResponse
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.time.Duration.Companion.hours
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

/** The Kotlin twin of `AgentMetricsHistoryTests` */
class AgentMetricsHistoryTest {
    private fun point(atSeconds: Long, cpu: Double?, temperature: Double?) = MetricsHistoryPoint(
        at = atSeconds * 1000,
        cpu_percent = cpu,
        mem_used_bytes = 1_073_741_824,
        mem_total_bytes = 4_294_967_296,
        disk_used_bytes = 5_368_709_120,
        disk_total_bytes = 107_374_182_400,
        load1 = 0.42,
        temperature_celsius = temperature,
    )

    private fun FakeAgentTransport.sent(): MetricsHistoryRequest =
        MetricsHistoryRequest.ADAPTER.decode(calls.last().second)

    // ------------------------------------------------------------- Routing

    @Test
    fun `history uses the agent only for the host the agent runs on`() {
        // Scenario A / the services host: the agent answers.
        assertEquals(
            ServiceControlRoute.AGENT,
            MetricsHistoryRouting.route(
                usesAgent = true,
                agentTransportAvailable = true,
                host = SSHHostID.HOME,
                agentHost = SSHHostID.HOME,
            ),
        )
        assertEquals(
            ServiceControlRoute.SSH,
            MetricsHistoryRouting.route(
                usesAgent = true,
                agentTransportAvailable = true,
                host = SSHHostID.VPS,
                agentHost = SSHHostID.HOME,
            ),
        )
    }

    @Test
    fun `a worker beyond the two slots reads its history over SSH`() {
        val third = SSHHostID.node("33333333-3333-3333-3333-333333333333")
        assertEquals(
            ServiceControlRoute.SSH,
            MetricsHistoryRouting.route(
                usesAgent = true,
                agentTransportAvailable = true,
                host = third,
                agentHost = SSHHostID.HOME,
            ),
        )
        assertEquals(
            ServiceControlRoute.AGENT,
            MetricsHistoryRouting.route(
                usesAgent = true,
                agentTransportAvailable = true,
                host = third,
                agentHost = third,
            ),
        )
    }

    @Test
    fun `an agentless deployment keeps reading history over SSH`() {
        for (host in listOf(SSHHostID.VPS, SSHHostID.HOME)) {
            assertEquals(
                ServiceControlRoute.SSH,
                MetricsHistoryRouting.route(false, agentTransportAvailable = true, host = host, agentHost = host),
            )
            assertEquals(
                ServiceControlRoute.SSH,
                MetricsHistoryRouting.route(false, agentTransportAvailable = false, host = host, agentHost = host),
            )
        }
        assertEquals(
            ServiceControlRoute.SSH,
            MetricsHistoryRouting.route(
                usesAgent = true,
                agentTransportAvailable = false,
                host = SSHHostID.HOME,
                agentHost = SSHHostID.HOME,
            ),
        )
    }

    // ------------------------------------------------------------- The wire

    @Test
    fun `every collector bucket travels by its own name`() = runTest {
        for (bucket in MetricsHistoryBucket.entries) {
            val transport = FakeAgentTransport()
            transport.reply("Control/MetricsHistory", MetricsHistoryResponse(bucket = bucket.rawValue))

            AgentMetricsHistory(AgentClient(transport)).history(bucket, SSHHostID.HOME)

            assertEquals(listOf("/gryonixnexusd.v1.Control/MetricsHistory"), transport.paths)
            assertEquals(bucket.rawValue, transport.sent().bucket)
        }
    }

    @Test
    fun `absent rates and temperature stay absent instead of becoming zero`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Control/MetricsHistory",
            MetricsHistoryResponse(
                bucket = "10s",
                points = listOf(
                    point(1_754_400_000, cpu = 12.5, temperature = 41.2),
                    point(1_754_400_010, cpu = null, temperature = null),
                ),
            ),
        )

        val points = AgentMetricsHistory(AgentClient(transport))
            .history(MetricsHistoryBucket.TEN_SECONDS, SSHHostID.HOME)

        assertEquals(2, points.size)
        assertEquals(12.5, points[0].cpuPercent)
        assertEquals(41.2, points[0].temperatureCelsius)
        assertEquals(Instant.ofEpochSecond(1_754_400_000), points[0].date)
        assertEquals(1_073_741_824, points[0].memUsedBytes)
        assertNull(points[1].cpuPercent)
        assertNull(points[1].temperatureCelsius)
        assertNull(points[1].netReceivedPerSecond)
        assertNull(points[1].diskWrittenPerSecond)
    }

    @Test
    fun `a window is applied on the server so undrawn rows are not transferred`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Control/MetricsHistory", MetricsHistoryResponse(bucket = "1m"))
        val now = Instant.ofEpochSecond(1_754_400_000)

        AgentMetricsHistory(AgentClient(transport), gate = null, window = 1.hours, now = { now })
            .history(MetricsHistoryBucket.ONE_MINUTE, SSHHostID.HOME)

        assertEquals((1_754_400_000L - 3_600L) * 1000, transport.sent().since)
    }

    @Test
    fun `without a window no lower bound is sent at all`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Control/MetricsHistory", MetricsHistoryResponse(bucket = "1w"))

        AgentMetricsHistory(AgentClient(transport))
            .history(MetricsHistoryBucket.ONE_WEEK, SSHHostID.HOME)

        assertEquals(0L, transport.sent().since)
    }
}
